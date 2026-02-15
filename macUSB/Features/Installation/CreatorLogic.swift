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

    // Local codesign helper (without sudo, executed in app process)
    func performLocalCodesign(on appURL: URL) throws {
        log("Uruchamiam lokalny codesign (bez sudo) na pliku w TEMP...")
        let path = appURL.path

        log("   xattr -cr ...")
        let xattrTask = Process()
        xattrTask.launchPath = "/usr/bin/xattr"
        xattrTask.arguments = ["-cr", path]
        try xattrTask.run()
        xattrTask.waitUntilExit()

        let componentsToSign = [
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAInstallerUtilities.framework/Versions/A/IAInstallerUtilities",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAMiniSoftwareUpdate.framework/Versions/A/IAMiniSoftwareUpdate",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAPackageKit.framework/Versions/A/IAPackageKit",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/IAESD",
            "\(path)/Contents/Resources/createinstallmedia"
        ]

        for component in componentsToSign {
            if FileManager.default.fileExists(atPath: component) {
                log("   Signing: \(URL(fileURLWithPath: component).lastPathComponent)")
                let task = Process()
                task.launchPath = "/usr/bin/codesign"
                task.arguments = ["-s", "-", "-f", component]
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    logError("Błąd codesign dla \(component) (kod: \(task.terminationStatus)) - kontynuuję mimo to.")
                }
            }
        }

        log("Lokalny codesign zakończony.")
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
