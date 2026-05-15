import Foundation

struct WindowsUEFIStatus {
    let hasEFIDirectory: Bool
    let hasAcceptedBootMarker: Bool

    var hasCompatibleEFI: Bool {
        hasEFIDirectory && hasAcceptedBootMarker
    }
}

extension HelperWorkflowExecutor {
    func runWindowsVerifyMediaStage(_ stage: WorkflowStage) throws {
        let targetPath = windowsPreparedTargetVolumePath ?? "/Volumes/\(request.targetLabel)"
        let targetURL = URL(fileURLWithPath: targetPath)

        guard fileManager.fileExists(atPath: targetPath) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie znaleziono zamontowanego woluminu docelowego po formatowaniu: \(targetPath)."
            )
        }

        let bootWimFound = fileManager.fileExists(atPath: targetURL.appendingPathComponent("sources/boot.wim").path)
            || fileManager.fileExists(atPath: targetURL.appendingPathComponent("Sources/boot.wim").path)
        guard bootWimFound else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Na nośniku USB nie znaleziono pliku sources/boot.wim."
            )
        }

        let uefiStatus = evaluateWindowsUEFIStatus(in: targetURL)
        guard uefiStatus.hasCompatibleEFI else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Na nośniku USB nie znaleziono wymaganych markerów UEFI (katalog EFI oraz co najmniej jeden plik: bootmgr.efi, EFI/Microsoft/Boot/cdboot.efi, EFI/BOOT/BOOTX64.EFI, EFI/BOOT/BOOTAA64.EFI)."
            )
        }

        if windowsShouldSplitWim {
            let swmFound = fileManager.fileExists(atPath: targetURL.appendingPathComponent("sources/install.swm").path)
                || fileManager.fileExists(atPath: targetURL.appendingPathComponent("Sources/install.swm").path)
            guard swmFound else {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Nie znaleziono pliku install.swm po podziale WIM."
                )
            }
        } else if windowsInstallWimPath != nil {
            let wimFound = fileManager.fileExists(atPath: targetURL.appendingPathComponent("sources/install.wim").path)
                || fileManager.fileExists(atPath: targetURL.appendingPathComponent("Sources/install.wim").path)
            guard wimFound else {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Nie znaleziono pliku install.wim po kopiowaniu nośnika."
                )
            }
        } else if windowsHasInstallESD {
            let esdFound = fileManager.fileExists(atPath: targetURL.appendingPathComponent("sources/install.esd").path)
                || fileManager.fileExists(atPath: targetURL.appendingPathComponent("Sources/install.esd").path)
            guard esdFound else {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Nie znaleziono pliku install.esd po kopiowaniu nośnika."
                )
            }
        }

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows media validation completed successfully.",
            shouldAdvancePercent: false
        )
    }

    func evaluateWindowsUEFIStatus(in rootURL: URL) -> WindowsUEFIStatus {
        let hasEFIDirectory = fileManager.fileExists(atPath: rootURL.appendingPathComponent("EFI").path)
            || fileManager.fileExists(atPath: rootURL.appendingPathComponent("efi").path)

        let bootCandidates = [
            "bootmgr.efi",
            "BOOTMGR.EFI",
            "EFI/Microsoft/Boot/cdboot.efi",
            "efi/microsoft/boot/cdboot.efi",
            "EFI/Microsoft/Boot/CDBOOT.EFI",
            "efi/microsoft/boot/CDBOOT.EFI",
            "EFI/BOOT/BOOTX64.EFI",
            "EFI/BOOT/BOOTAA64.EFI",
            "efi/boot/bootx64.efi",
            "efi/boot/bootaa64.efi",
            "efi/boot/BOOTX64.EFI",
            "efi/boot/BOOTAA64.EFI",
            "EFI/BOOT/bootx64.efi",
            "EFI/BOOT/bootaa64.efi"
        ]

        let hasAcceptedBootMarker = bootCandidates.contains { candidate in
            fileManager.fileExists(atPath: rootURL.appendingPathComponent(candidate).path)
        }

        return WindowsUEFIStatus(
            hasEFIDirectory: hasEFIDirectory,
            hasAcceptedBootMarker: hasAcceptedBootMarker
        )
    }

    func detachWindowsMountedSourceIfNeeded() {
        let explicitDevice = windowsMountedImageDevice?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitMountPath = windowsActiveSourceMountPath?.trimmingCharacters(in: .whitespacesAndNewlines)

        var detachTargets: [String] = []
        if let explicitDevice, !explicitDevice.isEmpty {
            detachTargets.append(explicitDevice)
        }
        if let explicitMountPath, !explicitMountPath.isEmpty {
            detachTargets.append(explicitMountPath)
        }

        let uniqueTargets = Array(Set(detachTargets))
        for target in uniqueTargets {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["detach", target, "-force"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                emitProgress(
                    stageKey: "windows_cleanup_temp",
                    titleKey: HelperWorkflowLocalizationKeys.windowsCleanupTempTitle,
                    percent: latestPercent,
                    statusKey: HelperWorkflowLocalizationKeys.windowsCleanupTempStatus,
                    logLine: "Windows cleanup: detached source image target=\(target), exit=\(process.terminationStatus)",
                    shouldAdvancePercent: false
                )
            } catch {
                emitProgress(
                    stageKey: "windows_cleanup_temp",
                    titleKey: HelperWorkflowLocalizationKeys.windowsCleanupTempTitle,
                    percent: latestPercent,
                    statusKey: HelperWorkflowLocalizationKeys.windowsCleanupTempStatus,
                    logLine: "Windows cleanup warning: detach \(target) failed: \(error.localizedDescription)",
                    shouldAdvancePercent: false
                )
            }
        }
    }
}
