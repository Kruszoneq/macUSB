import Foundation
import AppKit
import ServiceManagement
import Darwin

extension HelperServiceManager {
    func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return String(localized: "Włączony")
        case .notRegistered:
            return String(localized: "Nie zarejestrowany")
        case .requiresApproval:
            return String(localized: "Wymaga zatwierdzenia")
        case .notFound:
            return String(localized: "Nie znaleziono")
        @unknown default:
            return String(localized: "Nieznany")
        }
    }
    func isAppInstalledInApplications() -> Bool {
        let bundlePath = Bundle.main.bundleURL.standardized.path
        return bundlePath.hasPrefix("/Applications/")
    }
    func isLocationRequirementSatisfied() -> Bool {
        if isAppInstalledInApplications() {
            return true
        }
        #if DEBUG
        return Self.isRunningFromXcodeDevelopmentBuild()
        #else
        return false
        #endif
    }

    #if DEBUG
    static func isRunningFromXcodeDevelopmentBuild() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil {
            return true
        }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        let bundlePath = Bundle.main.bundleURL.standardized.path
        return bundlePath.contains("/DerivedData/") && bundlePath.contains("/Build/Products/")
    }
    #endif
    func presentMoveToApplicationsAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Wymagana lokalizacja /Applications")
        alert.informativeText = String(localized: "Aby używać helpera uprzywilejowanego, przenieś aplikację macUSB do katalogu Applications i uruchom ją ponownie.")
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }
    func presentApprovalRequiredAlert(onDismiss: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Wymagane narzędzie pomocnicze")
        alert.informativeText = String(localized: "macUSB wymaga zezwolenia na działanie w tle, aby umożliwić zarządzanie nośnikami. Przejdź do ustawień systemowych, aby nadać wymagane uprawnienia")
        alert.addButton(withTitle: String(localized: "Przejdź do ustawień systemowych"))
        alert.addButton(withTitle: String(localized: "Nie teraz"))

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
            onDismiss?()
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
    func presentRegistrationErrorAlertIfNeeded(error: Error, interactive: Bool) {
        guard interactive else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Nie udało się zarejestrować helpera")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }
    func presentAutomaticHelperUpdateFailureAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Nie udało się automatycznie zaktualizować helpera")
        alert.informativeText = String(localized: "macUSB wykrył nową wersję aplikacji, ale automatyczna aktualizacja helpera zakończyła się błędem. Wybierz Narzędzia → Napraw helpera i uruchom naprawę ręcznie.")
        alert.addButton(withTitle: String(localized: "Rozumiem"))
        presentAlert(alert)
    }
    func isOperationNotPermitted(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.code == Int(EPERM) || nsError.code == 1 {
            return true
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("operation not permitted")
    }
    func diagnosticErrorDescription(for error: Error) -> String {
        let nsError = error as NSError
        var details = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]
        if let debugDescription = nsError.userInfo["NSDebugDescription"] as? String,
           !debugDescription.isEmpty {
            details.append("debug=\(debugDescription)")
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlying=\(underlyingError.domain):\(underlyingError.code)")
        }
        return "\(nsError.localizedDescription) [\(details.joined(separator: ", "))]"
    }
    func isLikelyBackgroundTaskPolicyBlock(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "SMAppServiceErrorDomain" && nsError.code == 1
    }
    func isRunningFromXcodeSession() -> Bool {
        #if DEBUG
        return Self.isRunningFromXcodeDevelopmentBuild()
        #else
        return false
        #endif
    }
    func presentOperationSummary(success: Bool, message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = success ? .informational : .warning
        alert.messageText = success ? String(localized: "Operacja zakończona") : String(localized: "Operacja nie powiodła się")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }
    func presentAlert(_ alert: NSAlert) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
