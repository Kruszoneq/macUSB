import Foundation

extension HelperWorkflowExecutor {
    func validateWindowsBootRequirements(
        in rootURL: URL,
        stage: WorkflowStage,
        isTarget: Bool
    ) throws {
        guard let bootMode = request.windowsBootMode else {
            throw HelperExecutionError.invalidRequest("Brak trybu rozruchu dla workflow Windows.")
        }

        switch bootMode {
        case .bios:
            let requiredPaths = ["BOOTMGR", "boot/BCD", "sources/boot.wim"]
            let missing = requiredPaths.filter { !windowsItemExists(relativePath: $0, in: rootURL) }
            guard missing.isEmpty else {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Brak wymaganych markerów BIOS: \(missing.joined(separator: ", "))."
                )
            }

        case .uefi:
            if isTarget, !windowsItemExists(relativePath: "sources/boot.wim", in: rootURL) {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Na nośniku USB nie znaleziono pliku sources/boot.wim."
                )
            }

            let hasEFIDirectory = windowsItemExists(relativePath: "efi", in: rootURL)
            let acceptedMarkers = [
                "bootmgr.efi",
                "efi/microsoft/boot/cdboot.efi",
                "efi/boot/bootx64.efi",
                "efi/boot/bootaa64.efi"
            ]
            guard hasEFIDirectory,
                  acceptedMarkers.contains(where: { windowsItemExists(relativePath: $0, in: rootURL) }) else {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Nie znaleziono wymaganych markerów UEFI."
                )
            }
        }

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows boot markers verified: mode=\(bootMode.rawValue), location=\(isTarget ? "target" : "source")",
            shouldAdvancePercent: false
        )
    }

    func windowsItemExists(relativePath: String, in rootURL: URL) -> Bool {
        var currentURL = rootURL
        for component in relativePath.split(separator: "/").map(String.init) {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: nil,
                options: []
            ), let match = entries.first(where: {
                $0.lastPathComponent.compare(component, options: [.caseInsensitive, .literal]) == .orderedSame
            }) else {
                return false
            }
            currentURL = match
        }
        return fileManager.fileExists(atPath: currentURL.path)
    }
}
