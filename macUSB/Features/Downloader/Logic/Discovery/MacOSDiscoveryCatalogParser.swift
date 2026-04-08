import Foundation

extension MacOSCatalogService {
    func fetchStableInstallers(phase: @escaping PhaseSink) async throws -> [MacOSInstallerEntry] {
        try Task.checkCancellation()

        phase(String(localized: "Pobieranie katalogu Apple..."))
        AppLogging.info("Pobieranie katalogu installerow z Apple.", category: "Downloader")
        let catalogData = try await fetchData(from: Constants.catalogURL)
        let candidates = try parseCatalogCandidates(from: catalogData)
        AppLogging.info("W katalogu znaleziono \(candidates.count) kandydatow InstallAssistant.", category: "Downloader")

        phase(String(localized: "Analizowanie metadanych wersji..."))
        AppLogging.info("Rozpoczecie parsowania plikow .dist.", category: "Downloader")
        var entries: [MacOSInstallerEntry] = []
        entries.reserveCapacity(candidates.count + Constants.legacySupportMap.count)

        for candidate in candidates {
            try Task.checkCancellation()
            if let parsed = try await parseDistributionCandidate(candidate) {
                entries.append(parsed)
            }
        }

        phase(String(localized: "Dołączanie starszych wersji..."))
        AppLogging.info("Dolaczanie starszych wpisow z Apple Support.", category: "Downloader")
        let legacyEntries = try await fetchLegacySupportEntries()
        entries.append(contentsOf: legacyEntries)

        let uniqueEntries = deduplicated(entries)
        AppLogging.info("Po deduplikacji pozostalo \(uniqueEntries.count) wpisow stable.", category: "Downloader")

        phase(String(localized: "Sprawdzanie rozmiarów instalatorów..."))
        AppLogging.info("Rozpoczecie sprawdzania rozmiarow instalatorow.", category: "Downloader")
        let sizeProbeResult = try await enrichedWithInstallerSizes(uniqueEntries)
        AppLogging.info("Zakonczono sprawdzanie rozmiarow instalatorow.", category: "Downloader")
        logSizeProbeSummary(sizeProbeResult.summary)
        return sizeProbeResult.entries
    }

    func fetchDownloadManifest(
        for entry: MacOSInstallerEntry,
        phase: @escaping PhaseSink
    ) async throws -> DownloadManifest {
        try Task.checkCancellation()

        if isOldestInstallerTarget(entry) {
            return try await fetchOldestDownloadManifest(for: entry, phase: phase)
        }

        let majorVersion = entry.version.split(separator: ".").first.map(String.init) ?? ""
        let normalizedName = entry.name.lowercased()
        let supportedMajors: Set<String> = ["11", "12", "13", "14", "15", "26"]
        let supportedNameTokens = ["high sierra", "mojave", "catalina", "big sur", "monterey", "ventura", "sonoma", "sequoia", "tahoe"]
        let hasSupportedName = supportedNameTokens.contains { normalizedName.contains($0) }
        let isCatalina = normalizedName.contains("catalina") && entry.version.hasPrefix("10.15")
        guard supportedMajors.contains(majorVersion) || hasSupportedName || isCatalina else {
            throw DiscoveryError.unsupportedEntry
        }
        guard let productID = entry.catalogProductID, !productID.isEmpty else {
            throw DiscoveryError.unsupportedEntry
        }

        phase(String(localized: "Pobieranie manifestu wybranego systemu..."))
        let catalogData = try await fetchData(from: Constants.catalogURL)
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

    func parseCatalogCandidates(from data: Data) throws -> [CatalogCandidate] {
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
                    catalogSizeBytes: catalogSizeBytes
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
