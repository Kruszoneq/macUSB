import AppKit
import Foundation

extension UniversalInstallationView {
    func persistWindowsAutounattendConfiguration() {
        guard isWindowsWorkflow else { return }
        CreatorWindowsAutounattendSessionStore.shared.store(
            windowsAutounattendConfiguration,
            for: sourceAppURL,
            systemName: systemName,
            architecture: windowsArchitecture
        )
    }

    func loadWindowsAutounattendConfiguration() {
        guard isWindowsWorkflow else { return }
        var configuration = CreatorWindowsAutounattendSessionStore.shared.configuration(
            for: sourceAppURL,
            systemName: systemName,
            architecture: windowsArchitecture
        )
        configuration.macLocale = windowsAutounattendMacLocale
        configuration.normalize(for: CreatorWindowsAutounattendWindowsVersion.detected(
            from: systemName,
            architecture: windowsArchitecture
        ))
        windowsAutounattendConfiguration = configuration
    }

    func resolveWindowsAutounattendStartReadiness() -> Bool {
        guard isWindowsWorkflow else { return true }
        guard windowsAutounattendConfiguration.canStartWorkflow else {
            logError("Windows answer-file configuration blocked start: local account display name is invalid.", category: "WindowsInstallFlow")
            errorMessage = String(localized: "creator.windows.summary.autounattend.account_name.placeholder", table: "Creator")
            return false
        }
        errorMessage = ""
        return true
    }

    func resolveWindowsAutounattendExistingFileIfNeeded(completion: @escaping (Bool) -> Void) {
        guard isWindowsWorkflow,
              windowsAutounattendConfiguration.hasSelectedOption,
              windowsAutounattendConfiguration.existingFileDecision == nil,
              let existingPath = CreatorWindowsAutounattendSourceInspection.existingAutounattendPath(in: windowsMountedSourcePath) else {
            completion(true)
            return
        }

        log("Windows source answer file detected: path=\(existingPath).", category: "WindowsInstallFlow")

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "creator.windows.summary.autounattend.conflict.title", table: "Creator")
        alert.informativeText = String(localized: "creator.windows.summary.autounattend.conflict.body", table: "Creator")
        alert.addButton(withTitle: String(localized: "creator.windows.summary.autounattend.conflict.use_existing", table: "Creator"))
        alert.addButton(withTitle: String(localized: "creator.windows.summary.autounattend.conflict.replace", table: "Creator"))
        alert.addButton(withTitle: String(localized: "creator.windows.summary.autounattend.conflict.stop", table: "Creator"))

        let completionHandler = { (response: NSApplication.ModalResponse) in
            switch response {
            case .alertFirstButtonReturn:
                self.log("Windows source answer file retained; generated answer file disabled.", category: "WindowsInstallFlow")
                self.windowsAutounattendConfiguration.existingFileDecision = .useExisting
                self.persistWindowsAutounattendConfiguration()
                completion(true)
            case .alertSecondButtonReturn:
                self.log("Windows source answer file will be replaced with the generated answer file.", category: "WindowsInstallFlow")
                self.windowsAutounattendConfiguration.existingFileDecision = .replaceWithMacUSB
                self.persistWindowsAutounattendConfiguration()
                completion(true)
            default:
                self.log("Windows answer-file conflict cancelled by user.", category: "WindowsInstallFlow")
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
