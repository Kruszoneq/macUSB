import SwiftUI
import AppKit

// Shared installation utilities used by the helper-only flow
extension UniversalInstallationView {
    func showStartCreationAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Ostrzeżenie o utracie danych")
        alert.informativeText = String(localized: "Wszystkie dane na wybranym nośniku zostaną usunięte. Czy na pewno chcesz rozpocząć proces?")
        alert.addButton(withTitle: String(localized: "Nie"))
        alert.addButton(withTitle: String(localized: "Tak"))

        let completionHandler = { (response: NSApplication.ModalResponse) in
            if response == .alertSecondButtonReturn {
                self.startCreationProcessEntry()
            }
        }

        if let window = NSApp.windows.first {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            let response = alert.runModal()
            completionHandler(response)
        }
    }

    func log(_ message: String, category: String = "Installation") {
        AppLogging.info(message, category: category)
    }

    func logError(_ message: String, category: String = "Installation") {
        AppLogging.error(message, category: category)
    }

    func performEmergencyCleanup(mountPoint: URL, tempURL: URL) {
        log("Cleanup: odmontowuję \(mountPoint.path)")
        log("Cleanup: usuwam katalog TEMP \(tempURL.path)")

        let unmountTask = Process()
        unmountTask.launchPath = "/usr/bin/hdiutil"
        unmountTask.arguments = ["detach", mountPoint.path, "-force"]
        try? unmountTask.run()
        unmountTask.waitUntilExit()

        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    func showCancelAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "Czy na pewno chcesz przerwać?")
        alert.addButton(withTitle: String(localized: "Nie"))
        alert.addButton(withTitle: String(localized: "Tak"))

        let completionHandler = { (response: NSApplication.ModalResponse) in
            if response == .alertSecondButtonReturn {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.isCancelling = true
                }
                self.performImmediateCancellation()
            }
        }

        if let window = NSApp.windows.first {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            let response = alert.runModal()
            completionHandler(response)
        }
    }

    func performImmediateCancellation() {
        stopUSBMonitoring()
        cancelHelperWorkflowIfNeeded {
            DispatchQueue.global(qos: .userInitiated).async {
                self.unmountDMG()
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.isCancelled = true
                        self.navigateToFinish = false
                        self.isCancelling = false
                    }
                }
            }
        }
    }

    func unmountDMG() {
        let mountPoint = sourceAppURL.deletingLastPathComponent().path
        log("UnmountDMG: próba odmontowania \(mountPoint)")
        guard mountPoint.hasPrefix("/Volumes/") else { return }

        let task = Process()
        task.launchPath = "/usr/bin/hdiutil"
        task.arguments = ["detach", mountPoint, "-force"]
        try? task.run()
        task.waitUntilExit()
        log("UnmountDMG: polecenie zakończone")
    }

    func startUSBMonitoring() {
        guard !isProcessing,
              !isHelperWorking,
              !isCancelled,
              !isUSBDisconnectedLock,
              !navigateToFinish
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
        if isProcessing || isHelperWorking || isCancelled || isUSBDisconnectedLock || navigateToFinish {
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
        alert.messageText = String(localized: "Odłączono dysk USB")
        alert.informativeText = String(localized: "Dalsze działanie aplikacji zostanie zablokowane")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Kontynuuj"))

        let completionHandler = { (_: NSApplication.ModalResponse) in
            DispatchQueue.main.async {
                self.isTabLocked = false
                DispatchQueue.global(qos: .userInitiated).async {
                    self.unmountDMG()
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
            completionHandler(.alertFirstButtonReturn)
        }
    }
}
