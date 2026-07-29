import Foundation

final class MacOSLocalInstallerMetadataReader: @unchecked Sendable {
    private struct ImageContents: Sendable {
        var mobileAssetURLs: [URL] = []
        var systemVersionURLs: [URL] = []
        var legacyPackageURL: URL?
        var baseSystemImageURL: URL?
    }

    private static let mobileAssetNames = [
        "com_apple_MobileAsset_MacSoftwareUpdate.xml",
        "com_apple_MobileAsset_MacSoftwareUpdate.plist"
    ]

    private let legacyParser: MacOSLocalInstallerLegacyParser

    init(processRunner: MacOSLocalInstallerProcessRunner) {
        legacyParser = MacOSLocalInstallerLegacyParser(processRunner: processRunner)
    }

    func readIdentity(
        candidate: MacOSLocalInstallerCandidate,
        mountedImageURL: URL,
        imageManager: MacOSLocalInstallerDiskImageManager
    ) async throws -> MacOSLocalInstallerIdentity? {
        if let identity = try await readCanonicalMobileAssetIdentity(
            at: mountedImageURL
        ) {
            return identity
        }

        let contents = try await macOSLocalInstallerOffMain {
            try Self.enumerateImageContents(at: mountedImageURL)
        }

        if let identity = try await macOSLocalInstallerOffMain({
            try Task.checkCancellation()
            return Self.firstMobileAssetIdentity(in: contents.mobileAssetURLs)
        }) {
            return identity
        }

        let systemVersionURLs = Self.canonicalSystemVersionURLs(
            at: mountedImageURL
        ) + contents.systemVersionURLs
        if let identity = try await macOSLocalInstallerOffMain({
            try Task.checkCancellation()
            return Self.firstSystemVersionIdentity(in: systemVersionURLs)
        }) {
            return identity
        }

        if let packageURL = contents.legacyPackageURL {
            do {
                let fallbackVersion = try await macOSLocalInstallerOffMain {
                    try Task.checkCancellation()
                    return Self.installerVersionFromInstallInfo(
                        appURL: candidate.appURL
                    )
                }
                if let identity = try await legacyParser.readIdentity(
                    packageURL: packageURL,
                    fallbackVersion: fallbackVersion,
                    temporaryRoot: imageManager.temporaryRoot
                ) {
                    return identity
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLogging.error(
                    "Odczyt Distribution z \(packageURL.path) nie powiodl sie; sprawdzam kolejne zrodlo metadanych: \(error.localizedDescription)",
                    category: "Downloader"
                )
            }
        }

        guard let baseSystemImageURL = contents.baseSystemImageURL else {
            return nil
        }
        let nestedMountURL = try await imageManager.mount(
            imageURL: baseSystemImageURL,
            label: "base-system"
        )
        let canonicalNestedSystemVersionURLs = Self.canonicalSystemVersionURLs(
            at: nestedMountURL
        )
        if let identity = try await macOSLocalInstallerOffMain({
            try Task.checkCancellation()
            return Self.firstSystemVersionIdentity(
                in: canonicalNestedSystemVersionURLs
            )
        }) {
            return identity
        }

        let nestedContents = try await macOSLocalInstallerOffMain {
            try Self.enumerateImageContents(at: nestedMountURL)
        }
        return try await macOSLocalInstallerOffMain {
            try Task.checkCancellation()
            return Self.firstSystemVersionIdentity(
                in: canonicalNestedSystemVersionURLs
                    + nestedContents.systemVersionURLs
            )
        }
    }

    private func readCanonicalMobileAssetIdentity(
        at mountURL: URL
    ) async throws -> MacOSLocalInstallerIdentity? {
        try await macOSLocalInstallerOffMain {
            try Task.checkCancellation()

            let mobileAssetURLs = Self.mobileAssetNames.map {
                mountURL.appendingPathComponent($0)
            }
            if let identity = Self.firstMobileAssetIdentity(in: mobileAssetURLs) {
                return identity
            }
            return nil
        }
    }

    private static func canonicalSystemVersionURLs(at mountURL: URL) -> [URL] {
        [
            mountURL.appendingPathComponent(
                "System/Library/CoreServices/SystemVersion.plist"
            ),
            mountURL.appendingPathComponent(
                "BaseSystem/System/Library/CoreServices/SystemVersion.plist"
            )
        ]
    }

    private static func enumerateImageContents(
        at mountURL: URL
    ) throws -> ImageContents {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: mountURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsPackageDescendants],
            errorHandler: { url, error in
                AppLogging.error(
                    "Blad skanowania zamontowanego obrazu \(url.path): \(error.localizedDescription)",
                    category: "Downloader"
                )
                return true
            }
        ) else {
            return ImageContents()
        }

        var contents = ImageContents()
        var seenPaths = Set<String>()

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let name = fileURL.lastPathComponent
            let lowercasedName = name.lowercased()

            if mobileAssetNames.contains(where: {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }) {
                appendUnique(fileURL, to: &contents.mobileAssetURLs, seenPaths: &seenPaths)
            } else if lowercasedName == "systemversion.plist" {
                appendUnique(fileURL, to: &contents.systemVersionURLs, seenPaths: &seenPaths)
            } else if lowercasedName == "osinstall.mpkg",
                      contents.legacyPackageURL == nil {
                contents.legacyPackageURL = fileURL
            } else if lowercasedName == "basesystem.dmg",
                      contents.baseSystemImageURL == nil {
                // Intentionally do not skip Finder-hidden files for this legacy fallback.
                contents.baseSystemImageURL = fileURL
            }
        }
        return contents
    }

    private static func appendUnique(
        _ url: URL,
        to urls: inout [URL],
        seenPaths: inout Set<String>
    ) {
        if seenPaths.insert(url.standardizedFileURL.path).inserted {
            urls.append(url)
        }
    }

    private static func firstMobileAssetIdentity(
        in urls: [URL]
    ) -> MacOSLocalInstallerIdentity? {
        let orderedURLs = urls.sorted { firstURL, secondURL in
            mobileAssetPriority(firstURL) < mobileAssetPriority(secondURL)
        }
        for url in orderedURLs {
            if let propertyList = propertyList(at: url),
               let identity = firstIdentity(in: propertyList) {
                return identity
            }
        }
        return nil
    }

    private static func mobileAssetPriority(_ url: URL) -> Int {
        mobileAssetNames.firstIndex {
            $0.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame
        } ?? mobileAssetNames.count
    }

    private static func firstSystemVersionIdentity(
        in urls: [URL]
    ) -> MacOSLocalInstallerIdentity? {
        for url in urls {
            guard let dictionary = propertyList(at: url) as? [String: Any] else {
                continue
            }
            if let identity = MacOSLocalInstallerIdentity(
                version: dictionary["ProductVersion"] as? String,
                build: dictionary["ProductBuildVersion"] as? String
            ) {
                return identity
            }
        }
        return nil
    }

    private static func installerVersionFromInstallInfo(appURL: URL) -> String? {
        let installInfoURL = appURL.appendingPathComponent(
            "Contents/SharedSupport/InstallInfo.plist"
        )
        guard let dictionary = propertyList(at: installInfoURL) as? [String: Any] else {
            return nil
        }

        for key in ["Payload Image Info", "System Image Info"] {
            guard
                let imageInfo = dictionary[key] as? [String: Any],
                let version = imageInfo["version"] as? String,
                !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            return version
        }
        return nil
    }

    private static func propertyList(at url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    private static func firstIdentity(
        in propertyList: Any
    ) -> MacOSLocalInstallerIdentity? {
        if let dictionary = propertyList as? [String: Any] {
            if let identity = MacOSLocalInstallerIdentity(
                version: dictionary["OSVersion"] as? String,
                build: dictionary["Build"] as? String
            ) {
                return identity
            }
            if let identity = MacOSLocalInstallerIdentity(
                version: dictionary["ProductVersion"] as? String,
                build: dictionary["ProductBuildVersion"] as? String
            ) {
                return identity
            }
            for value in dictionary.values {
                if let identity = firstIdentity(in: value) {
                    return identity
                }
            }
        } else if let array = propertyList as? [Any] {
            for value in array {
                if let identity = firstIdentity(in: value) {
                    return identity
                }
            }
        }
        return nil
    }
}
