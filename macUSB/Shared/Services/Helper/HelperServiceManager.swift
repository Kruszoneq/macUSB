import Foundation
import AppKit
import ServiceManagement

final class HelperServiceManager {
    static let shared = HelperServiceManager()

    static let daemonPlistName = "com.kruszoneq.macusb.helper.plist"
    static let machServiceName = "com.kruszoneq.macusb.helper"

    #if DEBUG
    static let debugLegacyTerminalFallbackKey = "Debug.UseLegacyTerminalFlow"
    #endif

    private init() {}

    func bootstrapIfNeededAtStartup(completion: @escaping (Bool) -> Void) {
        #if DEBUG
        if Self.isRunningFromXcodeDevelopmentBuild() {
            completion(true)
            return
        }
        #endif

        ensureReadyForPrivilegedWork(interactive: true) { ready, _ in
            completion(ready)
        }
    }

    func ensureReadyForPrivilegedWork(completion: @escaping (Bool, String?) -> Void) {
        ensureReadyForPrivilegedWork(interactive: true, completion: completion)
    }

    func presentStatusAlert() {
        evaluateStatus { statusText in
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.alertStyle = .informational
            alert.messageText = String(localized: "Status helpera")
            alert.informativeText = statusText
            alert.addButton(withTitle: String(localized: "OK"))
            self.presentAlert(alert)
        }
    }

    func repairRegistrationFromMenu() {
        DispatchQueue.global(qos: .userInitiated).async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            do {
                if service.status != .notRegistered {
                    try service.unregister()
                }
                try service.register()
                DispatchQueue.main.async {
                    self.handlePostRegistrationStatus(interactive: true) { ready, message in
                        self.presentOperationSummary(success: ready, message: message ?? String(localized: "Naprawa helpera zakończona"))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentOperationSummary(success: false, message: error.localizedDescription)
                }
            }
        }
    }

    func unregisterFromMenu() {
        DispatchQueue.global(qos: .userInitiated).async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            do {
                try service.unregister()
                DispatchQueue.main.async {
                    self.presentOperationSummary(success: true, message: String(localized: "Helper został usunięty"))
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentOperationSummary(success: false, message: error.localizedDescription)
                }
            }
        }
    }

    private func ensureReadyForPrivilegedWork(interactive: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard isLocationRequirementSatisfied() else {
            let message = String(localized: "Aby uruchomić helper systemowy, aplikacja musi znajdować się w katalogu Applications.")
            if interactive {
                presentMoveToApplicationsAlert()
            }
            completion(false, message)
            return
        }

        let service = SMAppService.daemon(plistName: Self.daemonPlistName)

        switch service.status {
        case .enabled:
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: true, completion: completion)

        case .requiresApproval:
            if interactive {
                presentApprovalRequiredAlert()
            }
            completion(false, String(localized: "Helper wymaga zatwierdzenia w Ustawieniach systemowych."))

        case .notRegistered, .notFound:
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try service.register()
                    DispatchQueue.main.async {
                        self.handlePostRegistrationStatus(interactive: interactive, completion: completion)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.presentRegistrationErrorAlertIfNeeded(error: error, interactive: interactive)
                        completion(false, error.localizedDescription)
                    }
                }
            }

        @unknown default:
            completion(false, String(localized: "Nieznany status helpera."))
        }
    }

    private func handlePostRegistrationStatus(interactive: Bool, completion: @escaping (Bool, String?) -> Void) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        switch service.status {
        case .enabled:
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: false, completion: completion)
        case .requiresApproval:
            if interactive {
                presentApprovalRequiredAlert()
            }
            completion(false, String(localized: "Helper został zarejestrowany, ale wymaga zatwierdzenia przez użytkownika."))
        case .notRegistered, .notFound:
            completion(false, String(localized: "Nie udało się aktywować helpera."))
        @unknown default:
            completion(false, String(localized: "Nieznany status helpera po rejestracji."))
        }
    }

    private func validateEnabledServiceHealth(
        interactive: Bool,
        allowRecovery: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        PrivilegedOperationClient.shared.queryHealth { ok, details in
            if ok {
                completion(true, nil)
                return
            }

            guard allowRecovery else {
                completion(false, "Helper jest włączony, ale XPC nie odpowiada: \(details)")
                return
            }

            self.recoverRegistrationAfterHealthFailure(
                interactive: interactive,
                healthDetails: details,
                completion: completion
            )
        }
    }

    private func recoverRegistrationAfterHealthFailure(
        interactive: Bool,
        healthDetails: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            do {
                if service.status != .notRegistered {
                    try service.unregister()
                }
                try service.register()
                DispatchQueue.main.async {
                    self.handlePostRegistrationStatus(interactive: interactive) { ready, message in
                        guard ready else {
                            completion(false, message)
                            return
                        }
                        PrivilegedOperationClient.shared.queryHealth { recovered, recoveredDetails in
                            if recovered {
                                completion(true, nil)
                            } else {
                                completion(
                                    false,
                                    "Helper został ponownie zarejestrowany, ale XPC nadal nie działa: \(recoveredDetails). Poprzedni błąd: \(healthDetails)"
                                )
                            }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentRegistrationErrorAlertIfNeeded(error: error, interactive: interactive)
                    completion(
                        false,
                        "Helper nie odpowiada przez XPC (\(healthDetails)). Nie udało się ponownie zarejestrować helpera: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func evaluateStatus(completion: @escaping (String) -> Void) {
        var lines: [String] = []

        lines.append("Status usługi: \(statusDescription(SMAppService.daemon(plistName: Self.daemonPlistName).status))")
        lines.append("Mach service: \(Self.machServiceName)")

        if isAppInstalledInApplications() {
            lines.append(String(localized: "Lokalizacja aplikacji: /Applications (OK)"))
        } else {
            #if DEBUG
            if Self.isRunningFromXcodeDevelopmentBuild() {
                lines.append(String(localized: "Lokalizacja aplikacji: środowisko Xcode (bypass DEBUG)"))
            } else {
                lines.append(String(localized: "Lokalizacja aplikacji: poza /Applications"))
            }
            #else
            lines.append(String(localized: "Lokalizacja aplikacji: poza /Applications"))
            #endif
        }

        PrivilegedOperationClient.shared.queryHealth { ok, details in
            lines.append("XPC health: \(ok ? "OK" : "BŁĄD")")
            lines.append("Szczegóły: \(details)")
            completion(lines.joined(separator: "\n"))
        }
    }

    private func statusDescription(_ status: SMAppService.Status) -> String {
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

    private func isAppInstalledInApplications() -> Bool {
        let bundlePath = Bundle.main.bundleURL.standardized.path
        return bundlePath.hasPrefix("/Applications/")
    }

    private func isLocationRequirementSatisfied() -> Bool {
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

    private func presentMoveToApplicationsAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Wymagana lokalizacja /Applications")
        alert.informativeText = String(localized: "Aby używać helpera uprzywilejowanego, przenieś aplikację macUSB do katalogu Applications i uruchom ją ponownie.")
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }

    private func presentApprovalRequiredAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Wymagane zatwierdzenie helpera")
        alert.informativeText = String(localized: "Helper został zarejestrowany, ale wymaga zatwierdzenia w Ustawieniach systemowych, aby mógł wykonywać operacje uprzywilejowane.")
        alert.addButton(withTitle: String(localized: "Otwórz Ustawienia"))
        alert.addButton(withTitle: String(localized: "Nie teraz"))

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func presentRegistrationErrorAlertIfNeeded(error: Error, interactive: Bool) {
        guard interactive else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Nie udało się zarejestrować helpera")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }

    private func presentOperationSummary(success: Bool, message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = success ? .informational : .warning
        alert.messageText = success ? String(localized: "Operacja zakończona") : String(localized: "Operacja nie powiodła się")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }

    private func presentAlert(_ alert: NSAlert) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
