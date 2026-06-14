import AppKit
import Foundation

extension UniversalInstallationView {
    func persistWindowsAutounattendConfiguration() {
        guard isWindowsWorkflow else { return }
        CreatorWindowsAutounattendSessionStore.shared.store(
            windowsAutounattendConfiguration,
            for: sourceAppURL,
            systemName: systemName
        )
    }

    func loadWindowsAutounattendConfiguration() {
        guard isWindowsWorkflow else { return }
        windowsAutounattendConfiguration = CreatorWindowsAutounattendSessionStore.shared.configuration(
            for: sourceAppURL,
            systemName: systemName
        )
    }

    func resolveWindowsAutounattendStartReadiness() -> Bool {
        guard isWindowsWorkflow else { return true }
        guard windowsAutounattendConfiguration.canStartWorkflow else {
            errorMessage = String(localized: "installation.summary.windows.autounattend.account_name.validation")
            return false
        }
        errorMessage = ""
        return true
    }

    func resolveWindowsAutounattendExistingFileIfNeeded(completion: @escaping (Bool) -> Void) {
        guard isWindowsWorkflow,
              windowsAutounattendConfiguration.hasSelectedOption,
              windowsAutounattendConfiguration.existingFileDecision == nil,
              CreatorWindowsAutounattendSourceInspection.existingAutounattendPath(in: windowsMountedSourcePath) != nil else {
            completion(true)
            return
        }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "installation.summary.windows.autounattend.conflict.title")
        alert.informativeText = String(localized: "installation.summary.windows.autounattend.conflict.body")
        alert.addButton(withTitle: String(localized: "installation.summary.windows.autounattend.conflict.use_existing"))
        alert.addButton(withTitle: String(localized: "installation.summary.windows.autounattend.conflict.replace"))
        alert.addButton(withTitle: String(localized: "installation.summary.windows.autounattend.conflict.stop"))

        let completionHandler = { (response: NSApplication.ModalResponse) in
            switch response {
            case .alertFirstButtonReturn:
                self.windowsAutounattendConfiguration.existingFileDecision = .useExisting
                self.persistWindowsAutounattendConfiguration()
                completion(true)
            case .alertSecondButtonReturn:
                self.windowsAutounattendConfiguration.existingFileDecision = .replaceWithMacUSB
                self.persistWindowsAutounattendConfiguration()
                completion(true)
            default:
                self.windowsAutounattendConfiguration.existingFileDecision = nil
                self.persistWindowsAutounattendConfiguration()
                completion(false)
            }
        }

        if let window = NSApp.windows.first {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            completionHandler(alert.runModal())
        }
    }
}
