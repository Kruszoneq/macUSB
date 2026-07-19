import Foundation

extension AnalysisLogic {
    private static let windowsBIOSRequiredMarkers = [
        "bootmgr",
        "boot/bcd",
        "sources/boot.wim"
    ]

    private static let windowsBIOSDiagnosticMarkers = [
        "boot/boot.sdi",
        "boot/bootfix.bin",
        "boot/etfsboot.com"
    ]

    private static let windowsUEFIBootMarkers = [
        "bootmgr.efi",
        "efi/microsoft/boot/cdboot.efi",
        "efi/boot/bootx64.efi",
        "efi/boot/bootaa64.efi"
    ]

    func detectWindowsBootCapabilities(in mountURL: URL) -> WindowsBootCapabilities {
        let indexedPaths = indexWindowsBootMarkerPaths(in: mountURL)

        let biosPresentMarkers = (
            Self.windowsBIOSRequiredMarkers + Self.windowsBIOSDiagnosticMarkers
        )
        .filter(indexedPaths.contains)
        .sorted()
        let biosMissingRequiredMarkers = Self.windowsBIOSRequiredMarkers
            .filter { !indexedPaths.contains($0) }
            .sorted()
        let hasBIOS = biosMissingRequiredMarkers.isEmpty

        var uefiPresentMarkers: [String] = []
        if indexedPaths.contains("efi") {
            uefiPresentMarkers.append("efi/")
        }
        let presentUEFIBootMarkers = Self.windowsUEFIBootMarkers
            .filter(indexedPaths.contains)
            .sorted()
        uefiPresentMarkers.append(contentsOf: presentUEFIBootMarkers)

        var uefiMissingRequiredMarkers: [String] = []
        if !indexedPaths.contains("efi") {
            uefiMissingRequiredMarkers.append("efi/")
        }
        if presentUEFIBootMarkers.isEmpty {
            uefiMissingRequiredMarkers.append(contentsOf: Self.windowsUEFIBootMarkers)
        }
        let hasUEFI = indexedPaths.contains("efi") && !presentUEFIBootMarkers.isEmpty

        var detectedModes: Set<WindowsBootMode> = []
        if hasBIOS {
            detectedModes.insert(.bios)
        }
        if hasUEFI {
            detectedModes.insert(.uefi)
        }

        return WindowsBootCapabilities(
            detectedModes: detectedModes,
            eligibleModes: [],
            biosPresentMarkers: biosPresentMarkers,
            biosMissingRequiredMarkers: biosMissingRequiredMarkers,
            uefiPresentMarkers: uefiPresentMarkers.sorted(),
            uefiMissingRequiredMarkers: uefiMissingRequiredMarkers.sorted()
        )
    }

    private func indexWindowsBootMarkerPaths(in mountURL: URL) -> Set<String> {
        let directoriesToIndex = [
            "",
            "boot",
            "sources",
            "efi",
            "efi/microsoft",
            "efi/microsoft/boot",
            "efi/boot"
        ]

        var resolvedDirectories: [String: URL] = ["": mountURL]
        var indexedPaths: Set<String> = []

        for relativeDirectory in directoriesToIndex {
            let directoryURL: URL
            if relativeDirectory.isEmpty {
                directoryURL = mountURL
            } else {
                let parentPath = (relativeDirectory as NSString).deletingLastPathComponent
                let component = (relativeDirectory as NSString).lastPathComponent.lowercased()
                guard let parentURL = resolvedDirectories[parentPath],
                      let resolvedURL = caseInsensitiveChildURL(named: component, in: parentURL) else {
                    continue
                }
                directoryURL = resolvedURL
                resolvedDirectories[relativeDirectory] = resolvedURL
                indexedPaths.insert(relativeDirectory)
            }

            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                let normalizedPath = relativeDirectory.isEmpty
                    ? name
                    : "\(relativeDirectory)/\(name)"
                indexedPaths.insert(normalizedPath)
            }
        }

        return indexedPaths
    }

    private func caseInsensitiveChildURL(named normalizedName: String, in directoryURL: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return entries.first { $0.lastPathComponent.lowercased() == normalizedName }
    }
}
