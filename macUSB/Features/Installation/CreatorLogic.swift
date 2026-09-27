import SwiftUI
import AppKit

// Shared installation utilities used by the helper-only flow
extension UniversalInstallationView {
    func showStartCreationAlert() {
        beginUSBCreationOperationIfNeeded()
        guard windowsMacUSBootPreflightRequired else {
            continueStartCreationAlert()
            return
        }

        runWindowsMacUSBootPreflight { ready, message in
            guard ready else {
                errorMessage = message ?? String(localized: "Nie udało się automatycznie odświeżyć helpera. Otwórz Narzędzia → Napraw helpera i spróbuj ponownie.")
                finishUSBCreationOperationIfNeeded()
                return
            }
            continueStartCreationAlert()
        }
    }

    private func continueStartCreationAlert() {
        guard resolveWindowsAutounattendStartReadiness() else {
            finishUSBCreationOperationIfNeeded()
            return
        }

        resolveWindowsAutounattendExistingFileIfNeeded { shouldContinue in
            guard shouldContinue else {
                self.finishUSBCreationOperationIfNeeded()
                return
            }
            self.showConfirmedStartCreationAlert()
        }
    }

    private func showConfirmedStartCreationAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Ostrzeżenie o utracie danych")
        alert.informativeText = String(localized: "Wszystkie dane na wybranym nośniku zostaną usunięte. Czy na pewno chcesz rozpocząć proces?")
        alert.addButton(withTitle: String(localized: "Nie"))
        alert.addButton(withTitle: String(localized: "Tak"))

        let completionHandler = { (response: NSApplication.ModalResponse) in
            if response == .alertSecondButtonReturn {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.navigateToCreationProgress = true
                }
                self.startCreationProcessEntry()
            } else if self.isWindowsWorkflow {
                self.windowsAutounattendConfiguration.existingFileDecision = nil
                self.persistWindowsAutounattendConfiguration()
                self.finishUSBCreationOperationIfNeeded()
            } else {
                self.finishUSBCreationOperationIfNeeded()
            }
        }

        if let window = NSApp.windows.first {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            let response = alert.runModal()
            completionHandler(response)
        }
    }

    var creationLogWorkflow: AppLogging.Workflow {
        if isWindowsWorkflow { return .windows }
        if isLinuxWorkflow { return linuxFlowContext?.isRawImageSelection == true ? .raw : .linux }
        if isPPC { return .ppc }
        if isMavericks { return .mavericks }
        if isRestoreLegacy { return .legacyRestore }
        if isCatalina { return .catalina }
        if isSierra { return .sierra }
        return .macos
    }

    func log(_ message: String, category: String = "Installation") {
        AppLogging.info(message, stage: .usb, workflow: creationLogWorkflow)
    }

    func logError(_ message: String, category: String = "Installation") {
        AppLogging.error(message, stage: .usb, workflow: creationLogWorkflow)
    }

    func performEmergencyCleanup(mountPoint: URL, tempURL: URL) {
        let cleanupToken = AppActiveOperationRegistry.shared.begin(
            kind: .cleanup,
            context: "installation_emergency_cleanup"
        )
        defer { cleanupToken.finish() }
        log("Emergency cleanup: detaching \(mountPoint.path)")
        log("Emergency cleanup: removing temporary directory \(tempURL.path)")

        let unmountTask = Process()
        unmountTask.launchPath = "/usr/bin/hdiutil"
        unmountTask.arguments = ["detach", mountPoint.path, "-force"]
        try? unmountTask.run()
        unmountTask.waitUntilExit()

        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        log("Emergency cleanup completed: temporaryDirectoryExists=\(FileManager.default.fileExists(atPath: tempURL.path)).")
    }

    func resetFlowToStartImmediately() {
        NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
        isTabLocked = false
        rootIsActive = false
    }

    func returnToAnalysisViewPreservingSelection() {
        stopUSBMonitoring()
        isTabLocked = false
        rootIsActive = false
    }

    func showCreationProgressCancelAlert() {
        guard !isWindowsMacUSBootCancellationBlocked else {
            log(
                "Cancellation confirmation skipped: the macUSBoot stage cannot be interrupted.",
                category: "WindowsInstallFlow"
            )
            return
        }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Czy przerwać tworzenie nośnika?")
        alert.informativeText = String(localized: "Nośnik USB nie będzie zdatny do rozruchu, jeśli proces zostanie zatrzymany przed zakończeniem. Konieczne będzie ponowne przygotowanie urządzenia.")
        alert.addButton(withTitle: String(localized: "Kontynuuj"))
        alert.addButton(withTitle: String(localized: "Przerwij"))

        let completionHandler = { (response: NSApplication.ModalResponse) in
            guard response == .alertSecondButtonReturn else { return }
            guard !self.isWindowsMacUSBootCancellationBlocked else {
                self.log(
                    "Cancellation confirmation rejected: the helper entered the non-cancellable macUSBoot stage.",
                    category: "WindowsInstallFlow"
                )
                return
            }

            withAnimation(.easeInOut(duration: 0.35)) {
                self.isCancelling = true
            }
            self.performCancellationAndNavigateToFinish()
        }

        if let window = NSApp.windows.first {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            let response = alert.runModal()
            completionHandler(response)
        }
    }

    func performCancellationAndNavigateToFinish() {
        guard !isWindowsMacUSBootCancellationBlocked else {
            cancellationRequestedBeforeWorkflowStart = false
            withAnimation(.easeInOut(duration: 0.2)) {
                isCancelling = false
            }
            log(
                "Cancellation request skipped: the macUSBoot stage cannot be interrupted.",
                category: "WindowsInstallFlow"
            )
            return
        }

        stopUSBMonitoring()

        if activeHelperWorkflowID == nil {
            cancellationRequestedBeforeWorkflowStart = true
            return
        }

        cancelHelperWorkflowIfNeeded { cancellationAccepted in
            DispatchQueue.main.async {
                if cancellationAccepted {
                    self.log(
                        "Helper accepted cancellation; waiting for the final workflow result.",
                        category: self.isWindowsWorkflow ? "WindowsInstallFlow" : "Installation"
                    )
                } else {
                    self.cancellationRequestedBeforeWorkflowStart = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.isCancelling = false
                    }
                    self.log(
                        "Helper rejected cancellation; the workflow remains active.",
                        category: self.isWindowsWorkflow ? "WindowsInstallFlow" : "Installation"
                    )
                }
            }
        }
    }

    var isWindowsMacUSBootCancellationBlocked: Bool {
        isWindowsWorkflow
            && helperCurrentStageKey == CreationProgressWindowsMapping.installMacUSBootStageKey
    }

    func completeCancellationFlow() {
        log("Workflow cancelled; opening the finish screen.")
        if let token = usbProcessSleepBlockToken {
            SystemSleepBlocker.shared.end(token)
            usbProcessSleepBlockToken = nil
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            didCancelCreation = true
            cancellationRequestedBeforeWorkflowStart = false
            helperOperationFailed = false
            isProcessing = false
            isHelperWorking = false
            isCancelling = false
            navigateToFinish = true
        }
        finishUSBCreationOperationIfNeeded()
    }

    func unmountDMG() {
        let mountPoint = sourceAppURL.deletingLastPathComponent().path
        log("Source image detach requested: \(mountPoint)")
        guard mountPoint.hasPrefix("/Volumes/") else { return }

        let task = Process()
        task.launchPath = "/usr/bin/hdiutil"
        task.arguments = ["detach", mountPoint, "-force"]
        try? task.run()
        task.waitUntilExit()
        log("Source image detach command completed: \(mountPoint)")
    }

    func unmountSourceImageIfNeeded() {
        if isWindowsWorkflow {
            log("Source image detach skipped: Windows source mount is managed by the helper.")
            return
        }

        if let linuxMountPoint = linuxFlowContext?.mountPointURLForCleanup {
            let mountPath = linuxMountPoint.path
            log("Source image detach requested: \(mountPath)")

            let task = Process()
            task.launchPath = "/usr/bin/hdiutil"
            task.arguments = ["detach", mountPath, "-force"]
            try? task.run()
            task.waitUntilExit()

            log("Source image detach command completed: \(mountPath)")
            return
        }

        if linuxFlowContext != nil {
            log("Source image detach skipped: no mounted image path.")
            return
        }

        unmountDMG()
    }

    func startUSBMonitoring() {
        guard !isProcessing,
              !isHelperWorking,
              !isCancelled,
              !isUSBDisconnectedLock,
              !navigateToFinish,
              !navigateToCreationProgress
        else {
            return
        }

        usbCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.checkDriveAvailability()
        }
    }

    func stopUSBMonitoring() {
        usbCheckTimer?.invalidate()
        usbCheckTimer = nil
    }

    func checkDriveAvailability() {
        if isProcessing || isHelperWorking || isCancelled || isUSBDisconnectedLock || navigateToFinish || navigateToCreationProgress {
            stopUSBMonitoring()
            return
        }

        guard let drive = targetDrive else { return }
        let isReachable = (try? drive.url.checkResourceIsReachable()) ?? false
        if !isReachable {
            stopUSBMonitoring()
            showUSBDisconnectAlert()
        }
    }

    func showUSBDisconnectAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "Odłączono nośnik USB")
        alert.informativeText = String(localized: "Dalsze działanie aplikacji zostanie zablokowane")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Kontynuuj"))

        let completionHandler = { (_: NSApplication.ModalResponse) in
            DispatchQueue.main.async {
                self.isTabLocked = false
                DispatchQueue.global(qos: .userInitiated).async {
                    self.unmountSourceImageIfNeeded()
                }
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.isUSBDisconnectedLock = true
                    self.navigateToFinish = false
                }
            }
        }

        if let window = NSApp.windows.first {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            alert.runModal()
            completionHandler(NSApplication.ModalResponse.alertFirstButtonReturn)
        }
    }
}
