import Foundation

extension MacOSCatalogService {
    func fetchInstallers(
        includeBetaVersions: Bool,
        phase: @escaping PhaseSink
    ) async throws -> [MacOSInstallerEntry] {
        try Task.checkCancellation()

        phase(String(localized: "Pobieranie katalogu Apple..."))
        let sources = Constants.catalogSources(includeBetaVersions: includeBetaVersions)
        AppLogging.info(
            "Pobieranie katalogow installerow z Apple. Kanaly: \(sources.map(\.channel.rawValue).joined(separator: ", ")).",
            category: "Downloader"
        )

        var batches: [CatalogCandidateBatch] = []
        try await withThrowingTaskGroup(of: CatalogCandidateBatch.self) { group in
            for source in sources {
                group.addTask {
                    try await fetchCatalogCandidateBatch(from: source)
                }
            }

            for try await batch in group {
                batches.append(batch)
            }
        }

        let stableProductIDs = Set(
            batches
                .first(where: { $0.source.channel == .stable })?
                .candidates
                .map(\.productID) ?? []
        )

        phase(String(localized: "Analizowanie metadanych wersji..."))
        var entries: [MacOSInstallerEntry] = []
        try await withThrowingTaskGroup(of: [MacOSInstallerEntry].self) { group in
            for batch in batches {
                let eligibleCandidates: [CatalogCandidate]
                if batch.source.channel == .stable {
                    eligibleCandidates = batch.candidates
                } else {
                    eligibleCandidates = batch.candidates.filter {
                        !stableProductIDs.contains($0.productID)
                    }
                }

                group.addTask {
                    try await parseCatalogEntries(
                        eligibleCandidates,
                        source: batch.source,
                        totalCandidateCount: batch.candidates.count
                    )
                }
            }

            for try await sourceEntries in group {
                entries.append(contentsOf: sourceEntries)
            }
        }

        phase(String(localized: "Dołączanie starszych wersji..."))
        AppLogging.info("Dolaczanie starszych wpisow z Apple Support.", category: "Downloader")
        let legacyEntries = try await fetchLegacySupportEntries()
        entries.append(contentsOf: legacyEntries)

        let uniqueEntries = deduplicated(entries)
        AppLogging.info(
            "Po deduplikacji pozostalo \(uniqueEntries.count) wpisow ze wszystkich aktywnych kanalow.",
            category: "Downloader"
        )

        phase(String(localized: "Sprawdzanie rozmiarów instalatorów..."))
        AppLogging.info("Rozpoczecie sprawdzania rozmiarow instalatorow.", category: "Downloader")
        let sizeProbeResult = try await enrichedWithInstallerSizes(uniqueEntries)
        AppLogging.info("Zakonczono sprawdzanie rozmiarow instalatorow.", category: "Downloader")
        logSizeProbeSummary(sizeProbeResult.summary)
        return sizeProbeResult.entries
    }

    private func fetchCatalogCandidateBatch(from source: CatalogSource) async throws -> CatalogCandidateBatch {
        try Task.checkCancellation()

        let catalogData = try await fetchData(from: source.url)
        let candidates = try parseCatalogCandidates(
            from: catalogData,
            releaseChannel: source.channel,
            catalogURL: source.url
        )
        AppLogging.info(
            "Kanal \(source.channel.rawValue): znaleziono \(candidates.count) kandydatow InstallAssistant.",
            category: "Downloader"
        )
        return CatalogCandidateBatch(source: source, candidates: candidates)
    }

    private func parseCatalogEntries(
        _ candidates: [CatalogCandidate],
        source: CatalogSource,
        totalCandidateCount: Int
    ) async throws -> [MacOSInstallerEntry] {
        var entries: [MacOSInstallerEntry] = []
        entries.reserveCapacity(candidates.count)
        for candidate in candidates {
            try Task.checkCancellation()
            if let parsed = try await parseDistributionCandidate(candidate) {
                entries.append(parsed)
            }
        }

        AppLogging.info(
            "Kanal \(source.channel.rawValue): przeanalizowano \(candidates.count) z \(totalCandidateCount) kandydatow, zaakceptowano \(entries.count) wpisow.",
            category: "Downloader"
        )
        return entries
    }

    func fetchDownloadManifest(
        for entry: MacOSInstallerEntry,
        phase: @escaping PhaseSink
    ) async throws -> DownloadManifest {
        try Task.checkCancellation()

        if isOldestInstallerTarget(entry) {
            return try await fetchOldestDownloadManifest(for: entry, phase: phase)
        }

        guard isSupportedDownloadTarget(entry) else {
            throw DiscoveryError.unsupportedEntry
        }
        guard let productID = entry.catalogProductID, !productID.isEmpty else {
            throw DiscoveryError.unsupportedEntry
        }
        guard let catalogURL = entry.catalogURL, isAllowedHost(catalogURL) else {
            throw DiscoveryError.unsupportedEntry
        }

        phase(String(localized: "Pobieranie manifestu wybranego systemu..."))
        AppLogging.info(
            "Pobieranie manifestu productID=\(productID), channel=\(entry.releaseChannel.rawValue), catalog=\(catalogURL.absoluteString)",
            category: "Downloader"
        )
        let catalogData = try await fetchData(from: catalogURL)
        let products = try parseCatalogProducts(from: catalogData)
        guard let product = products[productID] else {
            throw DiscoveryError.productNotFound(productID)
        }
        let distributionURL: URL? = {
            guard
                let distributions = product["Distributions"] as? [String: Any],
                let url = preferredDistributionURL(from: distributions),
                isAllowedHost(url)
            else {
                return nil
            }
            return url
        }()

        phase(String(localized: "Analiza listy plików i metadanych..."))
        var descriptors = packageDescriptors(from: product)
        descriptors = descriptors.filter { descriptor in
            isAllowedHost(descriptor.url) && isDownloadAssetURL(descriptor.url)
        }
        if isLegacyAssemblyTarget(entry) {
            descriptors = filterLegacyAssemblyDescriptors(descriptors)
        } else {
            descriptors = filterModernAssemblyDescriptors(descriptors)
        }
        guard !descriptors.isEmpty else {
            throw DiscoveryError.emptyDownloadManifest
        }

        phase(String(localized: "Ustalanie rozmiarów plików..."))
        let probeState = SizeProbeRunState()
        var manifestItems: [DownloadManifestItem] = []
        manifestItems.reserveCapacity(descriptors.count)
        var totalExpectedBytes: Int64 = 0

        for (index, descriptor) in descriptors.enumerated() {
            try Task.checkCancellation()

            var expectedSizeBytes = descriptor.sizeBytes
            if expectedSizeBytes == nil || expectedSizeBytes == 0 {
                let result = try await fetchContentLengthWithRetry(from: descriptor.url, state: probeState)
                expectedSizeBytes = result.bytes
            }

            guard let resolvedSizeBytes = expectedSizeBytes, resolvedSizeBytes > 0 else {
                throw DiscoveryError.invalidResponse(descriptor.url)
            }

            let item = DownloadManifestItem(
                order: index,
                name: descriptor.name,
                url: descriptor.url,
                packageIdentifier: descriptor.packageIdentifier,
                expectedSizeBytes: resolvedSizeBytes,
                expectedDigest: descriptor.digest,
                digestAlgorithm: descriptor.digestAlgorithm,
                integrityDataURL: descriptor.integrityDataURL
            )
            manifestItems.append(item)
            totalExpectedBytes += resolvedSizeBytes
        }

        return DownloadManifest(
            productID: productID,
            systemName: entry.name,
            systemVersion: entry.version,
            systemBuild: entry.build,
            distributionURL: distributionURL,
            items: manifestItems,
            totalExpectedBytes: totalExpectedBytes
        )
    }

    private func fetchOldestDownloadManifest(
        for entry: MacOSInstallerEntry,
        phase: @escaping PhaseSink
    ) async throws -> DownloadManifest {
        guard entry.sourceURL.pathExtension.lowercased() == "dmg", isAllowedHost(entry.sourceURL) else {
            throw DiscoveryError.unsupportedEntry
        }

        phase(String(localized: "Przygotowanie manifestu dla najstarszego systemu..."))
        let probeState = SizeProbeRunState()
        let candidateURLs = sizeProbeURLs(for: entry.sourceURL)
        var selectedURL: URL?
        var resolvedSizeBytes: Int64?

        for candidateURL in candidateURLs {
            try Task.checkCancellation()
            guard isAllowedHost(candidateURL) else { continue }

            let sizeResult = try await fetchContentLengthWithRetry(from: candidateURL, state: probeState)
            if let bytes = sizeResult.bytes, bytes > 0 {
                selectedURL = candidateURL
                resolvedSizeBytes = bytes
                break
            }
        }

        guard let finalSourceURL = selectedURL, let finalSizeBytes = resolvedSizeBytes, finalSizeBytes > 0 else {
            throw DiscoveryError.invalidResponse(entry.sourceURL)
        }
        AppLogging.info(
            "Oldest manifest source selected: original=\(entry.sourceURL.absoluteString), final=\(finalSourceURL.absoluteString), size=\(finalSizeBytes)",
            category: "Downloader"
        )

        let item = DownloadManifestItem(
            order: 0,
            name: packageDisplayName(for: finalSourceURL),
            url: finalSourceURL,
            packageIdentifier: nil,
            expectedSizeBytes: finalSizeBytes,
            expectedDigest: nil,
            digestAlgorithm: nil,
            integrityDataURL: nil
        )

        return DownloadManifest(
            productID: entry.catalogProductID ?? "legacy-support-\(entry.version)",
            systemName: entry.name,
            systemVersion: entry.version,
            systemBuild: entry.build,
            distributionURL: nil,
            items: [item],
            totalExpectedBytes: finalSizeBytes
        )
    }

    func parseCatalogProducts(from data: Data) throws -> [String: [String: Any]] {
        guard
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let products = plist["Products"] as? [String: [String: Any]]
        else {
            throw DiscoveryError.invalidCatalogFormat
        }
        return products
    }

    func parseCatalogCandidates(
        from data: Data,
        releaseChannel: MacOSInstallerReleaseChannel,
        catalogURL: URL
    ) throws -> [CatalogCandidate] {
        let products = try parseCatalogProducts(from: data)

        var candidates: [CatalogCandidate] = []
        candidates.reserveCapacity(products.count)

        for (productID, product) in products {
            guard
                let extendedMeta = product["ExtendedMetaInfo"] as? [String: Any],
                extendedMeta["InstallAssistantPackageIdentifiers"] != nil
            else {
                continue
            }

            guard
                let distributions = product["Distributions"] as? [String: Any],
                let distributionURL = preferredDistributionURL(from: distributions)
            else {
                continue
            }

            let packageDescriptors = packageDescriptors(from: product)
            let sourceURL = preferredInstallAssistantPackageURL(from: packageDescriptors) ?? distributionURL
            let catalogSizeBytes = summedPackageSize(from: packageDescriptors)
            candidates.append(
                CatalogCandidate(
                    productID: productID,
                    distributionURL: distributionURL,
                    sourceURL: sourceURL,
                    catalogSizeBytes: catalogSizeBytes,
                    releaseChannel: releaseChannel,
                    catalogURL: catalogURL
                )
            )
        }

        return candidates
    }

    func preferredDistributionURL(from distributions: [String: Any]) -> URL? {
        let preferredKeys = ["English", "en", "en_US", "en_GB", "en_AU"]

        for key in preferredKeys {
            if let urlString = distributions[key] as? String, let url = URL(string: urlString) {
                return url
            }
        }

        for value in distributions.values {
            if let urlString = value as? String, let url = URL(string: urlString) {
                return url
            }
        }

        return nil
    }

    func preferredInstallAssistantPackageURL(from descriptors: [CatalogPackageDescriptor]) -> URL? {
        for descriptor in descriptors {
            if descriptor.name.localizedCaseInsensitiveContains("InstallAssistant") {
                return descriptor.url
            }
        }
        return nil
    }

    func summedPackageSize(from descriptors: [CatalogPackageDescriptor]) -> Int64? {
        guard !descriptors.isEmpty else {
            return nil
        }

        var totalBytes: Int64 = 0
        for descriptor in descriptors {
            if let sizeBytes = descriptor.sizeBytes {
                totalBytes += max(0, sizeBytes)
            }
        }

        return totalBytes > 0 ? totalBytes : nil
    }

    func packageDescriptors(from product: [String: Any]) -> [CatalogPackageDescriptor] {
        guard let packages = product["Packages"] as? [[String: Any]] else {
            return []
        }

        var descriptors: [CatalogPackageDescriptor] = []
        descriptors.reserveCapacity(packages.count)

        for package in packages {
            guard
                let urlString = package["URL"] as? String,
                let url = URL(string: urlString)
            else {
                continue
            }

            let integrityURL: URL?
            if let integrityString = package["IntegrityDataURL"] as? String {
                integrityURL = URL(string: integrityString)
            } else {
                integrityURL = nil
            }

            let descriptor = CatalogPackageDescriptor(
                name: packageDisplayName(for: url),
                url: url,
                packageIdentifier: (package["PackageIdentifier"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                sizeBytes: parseInt64(from: package["Size"]),
                digest: (package["Digest"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                digestAlgorithm: (package["DigestAlgorithm"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                integrityDataURL: integrityURL
            )
            descriptors.append(descriptor)
        }

        return descriptors
    }

    func packageDisplayName(for url: URL) -> String {
        let lastComponent = url.lastPathComponent
        if !lastComponent.isEmpty {
            return lastComponent
        }
        return url.absoluteString
    }

    func parseInt64(from value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let intValue = value as? Int64 {
            return intValue
        }
        if let intValue = value as? Int {
            return Int64(intValue)
        }
        if let stringValue = value as? String, let intValue = Int64(stringValue) {
            return intValue
        }
        return nil
    }
}
