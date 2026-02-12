import Foundation
import SwiftUI

extension UniversalInstallationView {
    func startCreationProcessEntry() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: HelperServiceManager.debugLegacyTerminalFallbackKey) {
            startCreationProcess()
            return
        }
        #endif

        startCreationProcessWithHelper()
    }

    private func startCreationProcessWithHelper() {
        guard let drive = targetDrive else {
            errorMessage = String(localized: "Błąd: Nie wybrano dysku.")
            return
        }

        withAnimation(.easeInOut(duration: 0.4)) {
            isTabLocked = true
            isProcessing = true
        }

        processingTitle = String(localized: "Rozpoczynanie...")
        processingSubtitle = String(localized: "Przygotowywanie operacji...")
        isTerminalWorking = false
        showFinishButton = false
        processSuccess = false
        errorMessage = ""
        navigateToFinish = false
        terminalFailed = false
        stopUSBMonitoring()
        showAuthWarning = false
        isRollingBack = false
        monitoringWarmupCounter = 0
        processingIcon = "lock.shield.fill"
        isCancelled = false
        helperProgressPercent = 0
        helperStageTitle = String(localized: "Przygotowanie")
        helperStatusText = String(localized: "Sprawdzanie gotowości helpera...")

        HelperServiceManager.shared.ensureReadyForPrivilegedWork { ready, failureReason in
            guard ready else {
                withAnimation {
                    isProcessing = false
                    isTerminalWorking = false
                    isTabLocked = false
                    startUSBMonitoring()
                    errorMessage = failureReason ?? String(localized: "Helper nie jest gotowy do pracy.")
                }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = try prepareHelperWorkflowRequest(for: drive)
                    DispatchQueue.main.async {
                        withAnimation {
                            isProcessing = false
                            isTerminalWorking = true
                            helperProgressPercent = 0
                            helperStageTitle = String(localized: "Uruchamianie helpera")
                            helperStatusText = String(localized: "Nawiązywanie połączenia XPC...")
                        }

                        PrivilegedOperationClient.shared.startWorkflow(
                            request: request,
                            onEvent: { event in
                                guard event.workflowID == activeHelperWorkflowID else { return }
                                helperProgressPercent = max(helperProgressPercent, min(event.percent, 100))
                                helperStageTitle = event.stageTitle
                                helperStatusText = event.statusText
                            },
                            onCompletion: { result in
                                guard result.workflowID == activeHelperWorkflowID else { return }

                                activeHelperWorkflowID = nil
                                isTerminalWorking = false

                                if result.isUserCancelled || isCancelled {
                                    return
                                }

                                terminalFailed = !result.success

                                if !result.success, let errorMessageText = result.errorMessage {
                                    logError("Helper zakończył się błędem: \(errorMessageText)", category: "Installation")
                                }

                                withAnimation {
                                    navigateToFinish = true
                                }
                            },
                            onStartError: { message in
                                activeHelperWorkflowID = nil
                                logError("Start helper workflow nieudany: \(message)", category: "Installation")
                                withAnimation {
                                    isProcessing = false
                                    isTerminalWorking = false
                                    isTabLocked = false
                                    startUSBMonitoring()
                                    errorMessage = message
                                }
                            },
                            onStarted: { workflowID in
                                activeHelperWorkflowID = workflowID
                                helperStageTitle = String(localized: "Rozpoczynanie...")
                                helperStatusText = String(localized: "Helper uruchamia pierwszy etap operacji uprzywilejowanych...")
                                log("Uruchomiono helper workflow: \(workflowID)")
                            }
                        )
                    }
                } catch {
                    DispatchQueue.main.async {
                        withAnimation {
                            isProcessing = false
                            isTerminalWorking = false
                            isTabLocked = false
                            startUSBMonitoring()
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private func prepareHelperWorkflowRequest(for drive: USBDrive) throws -> HelperWorkflowRequestPayload {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: tempWorkURL.path) {
            try fileManager.createDirectory(at: tempWorkURL, withIntermediateDirectories: true)
        }

        let shouldPreformat = drive.needsFormatting && !isPPC
        let sourceIsMountedVolume = sourceAppURL.path.hasPrefix("/Volumes/")

        if isRestoreLegacy {
            let sourceESD = sourceAppURL.appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")
            guard fileManager.fileExists(atPath: sourceESD.path) else {
                throw NSError(
                    domain: "macUSB",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono pliku InstallESD.dmg.")]
                )
            }

            let targetESD = tempWorkURL.appendingPathComponent("InstallESD.dmg")
            if fileManager.fileExists(atPath: targetESD.path) {
                try fileManager.removeItem(at: targetESD)
            }
            try fileManager.copyItem(at: sourceESD, to: targetESD)

            return HelperWorkflowRequestPayload(
                workflowKind: .legacyRestore,
                systemName: systemName,
                sourcePath: targetESD.path,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: shouldPreformat,
                isCatalina: false,
                requiresApplicationPathArg: false,
                postInstallSourceAppPath: nil
            )
        }

        if isMavericks {
            let sourceImage = originalImageURL ?? sourceAppURL
            guard fileManager.fileExists(atPath: sourceImage.path) else {
                throw NSError(
                    domain: "macUSB",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono źródłowego pliku obrazu.")]
                )
            }

            let targetImage = tempWorkURL.appendingPathComponent("InstallESD.dmg")
            if fileManager.fileExists(atPath: targetImage.path) {
                try fileManager.removeItem(at: targetImage)
            }
            try fileManager.copyItem(at: sourceImage, to: targetImage)

            return HelperWorkflowRequestPayload(
                workflowKind: .mavericks,
                systemName: systemName,
                sourcePath: targetImage.path,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: shouldPreformat,
                isCatalina: false,
                requiresApplicationPathArg: false,
                postInstallSourceAppPath: nil
            )
        }

        if isPPC {
            let mountedVolumeSource = sourceAppURL.deletingLastPathComponent().path
            let restoreSource: String

            if mountedVolumeSource.hasPrefix("/Volumes/"),
               fileManager.fileExists(atPath: mountedVolumeSource) {
                restoreSource = mountedVolumeSource
                log("PPC helper strategy: asr restore from mounted source -> /Volumes/PPC", category: "Installation")
            } else if let imageURL = originalImageURL, fileManager.fileExists(atPath: imageURL.path) {
                let stagedImageURL = tempWorkURL.appendingPathComponent("PPC_\(imageURL.lastPathComponent)")
                if fileManager.fileExists(atPath: stagedImageURL.path) {
                    try fileManager.removeItem(at: stagedImageURL)
                }
                try fileManager.copyItem(at: imageURL, to: stagedImageURL)
                restoreSource = stagedImageURL.path
                log("PPC helper strategy: asr restore from staged image fallback -> /Volumes/PPC", category: "Installation")
            } else {
                throw NSError(
                    domain: "macUSB",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono źródła PPC do przywracania.")]
                )
            }

            log("PPC helper source: \(restoreSource)", category: "Installation")

            return HelperWorkflowRequestPayload(
                workflowKind: .ppc,
                systemName: systemName,
                sourcePath: restoreSource,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: false,
                isCatalina: false,
                requiresApplicationPathArg: false,
                postInstallSourceAppPath: nil
            )
        }

        var effectiveAppURL = sourceAppURL

        if isSierra {
            let destinationAppURL = tempWorkURL.appendingPathComponent(sourceAppURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationAppURL.path) {
                try fileManager.removeItem(at: destinationAppURL)
            }
            try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)

            let plistPath = destinationAppURL.appendingPathComponent("Contents/Info.plist").path
            let plutilTask = Process()
            plutilTask.launchPath = "/usr/bin/plutil"
            plutilTask.arguments = ["-replace", "CFBundleShortVersionString", "-string", "12.6.03", plistPath]
            try plutilTask.run()
            plutilTask.waitUntilExit()

            let xattrTask = Process()
            xattrTask.launchPath = "/usr/bin/xattr"
            xattrTask.arguments = ["-dr", "com.apple.quarantine", destinationAppURL.path]
            try xattrTask.run()
            xattrTask.waitUntilExit()

            let createInstallMediaPath = destinationAppURL.appendingPathComponent("Contents/Resources/createinstallmedia").path
            let codesignTask = Process()
            codesignTask.launchPath = "/usr/bin/codesign"
            codesignTask.arguments = ["-s", "-", "-f", createInstallMediaPath]
            try codesignTask.run()
            codesignTask.waitUntilExit()

            effectiveAppURL = destinationAppURL
        } else if sourceIsMountedVolume || isCatalina || needsCodesign {
            let destinationAppURL = tempWorkURL.appendingPathComponent(sourceAppURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationAppURL.path) {
                try fileManager.removeItem(at: destinationAppURL)
            }
            try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)

            if isCatalina || needsCodesign {
                try performLocalCodesign(on: destinationAppURL)
            }

            effectiveAppURL = destinationAppURL
        }

        return HelperWorkflowRequestPayload(
            workflowKind: .standard,
            systemName: systemName,
            sourcePath: effectiveAppURL.path,
            targetVolumePath: drive.url.path,
            targetBSDName: drive.device,
            targetLabel: drive.url.lastPathComponent,
            needsPreformat: shouldPreformat,
            isCatalina: isCatalina,
            requiresApplicationPathArg: isLegacySystem || isSierra,
            postInstallSourceAppPath: isCatalina ? sourceAppURL.resolvingSymlinksInPath().path : nil
        )
    }

    func cancelHelperWorkflowIfNeeded(completion: @escaping () -> Void) {
        guard let workflowID = activeHelperWorkflowID else {
            completion()
            return
        }

        log("Wysyłam żądanie anulowania helper workflow: \(workflowID)")

        PrivilegedOperationClient.shared.cancelWorkflow(workflowID) { _, _ in
            PrivilegedOperationClient.shared.clearHandlers(for: workflowID)
            activeHelperWorkflowID = nil
            isTerminalWorking = false
            completion()
        }
    }

}
