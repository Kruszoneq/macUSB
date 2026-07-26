import Foundation

extension MacOSCatalogService {
    func isOldestInstallerTarget(_ entry: MacOSInstallerEntry) -> Bool {
        guard entry.catalogProductID == nil else {
            return false
        }
        guard entry.sourceURL.pathExtension.lowercased() == "dmg" else {
            return false
        }

        let versionParts = entry.version.split(separator: ".")
        guard let majorPart = versionParts.first, let major = Int(majorPart) else {
            return false
        }
        guard major == 10 else {
            return false
        }

        let minor = versionParts.dropFirst().first.flatMap { Int($0) } ?? -1
        return minor >= 7 && minor <= 12
    }

    func isLegacyAssemblyTarget(_ entry: MacOSInstallerEntry) -> Bool {
        let normalized = entry.name.lowercased()
        if normalized.contains("catalina"), entry.version.hasPrefix("10.15") {
            return true
        }
        if normalized.contains("mojave"), entry.version.hasPrefix("10.14") {
            return true
        }
        if normalized.contains("high sierra"), entry.version.hasPrefix("10.13") {
            return true
        }
        return false
    }

    func filterLegacyAssemblyDescriptors(_ descriptors: [CatalogPackageDescriptor]) -> [CatalogPackageDescriptor] {
        let requiredIDs = Set(Constants.legacyAssemblyRequiredPackageIdentifiers.map { $0.lowercased() })
        let requiredNames = Set(Constants.legacyAssemblyRequiredFileNames.map { $0.lowercased() })

        var filtered = descriptors.filter { descriptor in
            if let packageIdentifier = descriptor.packageIdentifier?.lowercased(), requiredIDs.contains(packageIdentifier) {
                return true
            }
            return requiredNames.contains(descriptor.url.lastPathComponent.lowercased())
        }

        let idPriority = Dictionary(
            uniqueKeysWithValues: Constants.legacyAssemblyRequiredPackageIdentifiers.enumerated().map { ($1.lowercased(), $0) }
        )
        let namePriority = Dictionary(
            uniqueKeysWithValues: Constants.legacyAssemblyRequiredFileNames.enumerated().map { ($1.lowercased(), $0) }
        )

        filtered.sort { lhs, rhs in
            let lhsRank = lhs.packageIdentifier.flatMap { idPriority[$0.lowercased()] }
                ?? namePriority[lhs.url.lastPathComponent.lowercased()]
                ?? Int.max
            let rhsRank = rhs.packageIdentifier.flatMap { idPriority[$0.lowercased()] }
                ?? namePriority[rhs.url.lastPathComponent.lowercased()]
                ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.name < rhs.name
        }

        return filtered
    }

    func filterModernAssemblyDescriptors(_ descriptors: [CatalogPackageDescriptor]) -> [CatalogPackageDescriptor] {
        let installAssistantDescriptors = descriptors.filter { descriptor in
            let packageID = descriptor.packageIdentifier?.lowercased() ?? ""
            let fileName = descriptor.url.lastPathComponent.lowercased()
            return fileName == "installassistant.pkg"
                || descriptor.name.lowercased() == "installassistant.pkg"
                || packageID.contains("installassistant")
        }

        guard !installAssistantDescriptors.isEmpty else {
            return descriptors
        }

        // Modern workflow should use a single InstallAssistant package in the download list.
        if let exactFileName = installAssistantDescriptors.first(where: {
            $0.url.lastPathComponent.caseInsensitiveCompare("InstallAssistant.pkg") == .orderedSame
        }) {
            return [exactFileName]
        }
        return [installAssistantDescriptors[0]]
    }

    func deduplicated(_ entries: [MacOSInstallerEntry]) -> [MacOSInstallerEntry] {
        var seen: Set<String> = []
        var result: [MacOSInstallerEntry] = []
        result.reserveCapacity(entries.count)

        for entry in entries {
            let key = "\(entry.releaseChannel.rawValue)|\(entry.name)|\(entry.version)|\(entry.build)"
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }

        return result
    }

    func isSupportedDownloadTarget(_ entry: MacOSInstallerEntry) -> Bool {
        if isOldestInstallerTarget(entry) {
            return true
        }

        let normalizedName = entry.name.lowercased()
        let majorVersion = entry.version.split(separator: ".").first.map(String.init) ?? ""
        let supportedMajors: Set<String> = ["11", "12", "13", "14", "15", "26", "27"]
        let supportedNameTokens = [
            "high sierra",
            "mojave",
            "catalina",
            "big sur",
            "monterey",
            "ventura",
            "sonoma",
            "sequoia",
            "tahoe",
            "golden gate"
        ]
        let hasSupportedName = supportedNameTokens.contains { normalizedName.contains($0) }
        let isCatalina = normalizedName.contains("catalina") && entry.version.hasPrefix("10.15")
        return supportedMajors.contains(majorVersion) || hasSupportedName || isCatalina
    }

    func isDownloadAssetURL(_ url: URL) -> Bool {
        Constants.downloadableExtensions.contains(url.pathExtension.lowercased())
    }
}
