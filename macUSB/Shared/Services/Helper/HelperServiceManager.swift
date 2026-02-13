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

    private typealias EnsureCompletion = (Bool, String?) -> Void
    private let coordinationQueue = DispatchQueue(label: "macUSB.helper.registration", qos: .userInitiated)
    private var ensureInProgress = false
    private var pendingEnsureCompletions: [EnsureCompletion] = []
    private var pendingEnsureInteractive = false

    private init() {}

    func bootstrapIfNeededAtStartup(completion: @escaping (Bool) -> Void) {
        #if DEBUG
        if Self.isRunningFromXcodeDevelopmentBuild() {
            completion(true)
            return
        }
        #endif

        ensureReadyForPrivilegedWork(interactive: false) { ready, _ in
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
        ensureReadyForPrivilegedWork(interactive: true) { ready, message in
            self.presentOperationSummary(
                success: ready,
                message: message ?? String(localized: "Naprawa helpera zakończona")
            )
        }
    }

    func unregisterFromMenu() {
        coordinationQueue.async {
            if self.ensureInProgress {
                DispatchQueue.main.async {
                    self.presentOperationSummary(
                        success: false,
                        message: String(localized: "Trwa inna operacja helpera. Poczekaj chwilę i spróbuj ponownie.")
                    )
                }
                return
            }

            let service = SMAppService.daemon(plistName: Self.daemonPlistName)

            do {
                if service.status == .notRegistered || service.status == .notFound {
                    DispatchQueue.main.async {
                        self.presentOperationSummary(success: true, message: String(localized: "Helper jest już usunięty"))
                    }
                    return
                }

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

        queueEnsureRequest(interactive: interactive, completion: completion)
    }

    private func queueEnsureRequest(interactive: Bool, completion: @escaping EnsureCompletion) {
        coordinationQueue.async {
            self.pendingEnsureCompletions.append(completion)
            self.pendingEnsureInteractive = self.pendingEnsureInteractive || interactive

            guard !self.ensureInProgress else {
                AppLogging.info(
                    "Wykryto równoległe żądanie gotowości helpera - dołączam do trwającej operacji.",
                    category: "Installation"
                )
                return
            }

            self.ensureInProgress = true
            let runInteractive = self.pendingEnsureInteractive
            self.runEnsureFlow(interactive: runInteractive)
        }
    }

    private func runEnsureFlow(interactive: Bool) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        switch service.status {
        case .enabled:
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: true) { ready, message in
                self.finalizeEnsureRequests(ready: ready, message: message)
            }

        case .requiresApproval:
            if interactive {
                DispatchQueue.main.async {
                    self.presentApprovalRequiredAlert()
                }
            }
            finalizeEnsureRequests(
                ready: false,
                message: String(localized: "Helper wymaga zatwierdzenia w Ustawieniach systemowych.")
            )

        case .notRegistered, .notFound:
            registerAndValidate(interactive: interactive) { ready, message in
                self.finalizeEnsureRequests(ready: ready, message: message)
            }

        @unknown default:
            finalizeEnsureRequests(ready: false, message: String(localized: "Nieznany status helpera."))
        }
    }

    private func registerAndValidate(interactive: Bool, completion: @escaping EnsureCompletion) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        do {
            try service.register()
            handlePostRegistrationStatus(interactive: interactive, completion: completion)
        } catch {
            if service.status == .enabled {
                AppLogging.info(
                    "register() zwrócił błąd, ale helper jest oznaczony jako enabled. Kontynuuję walidację.",
                    category: "Installation"
                )
                handlePostRegistrationStatus(interactive: interactive, completion: completion)
                return
            }

            DispatchQueue.main.async {
                self.presentRegistrationErrorAlertIfNeeded(error: error, interactive: interactive)
            }
            completion(false, error.localizedDescription)
        }
    }

    private func finalizeEnsureRequests(ready: Bool, message: String?) {
        coordinationQueue.async {
            let completions = self.pendingEnsureCompletions
            self.pendingEnsureCompletions.removeAll()
            self.pendingEnsureInteractive = false
            self.ensureInProgress = false

            DispatchQueue.main.async {
                completions.forEach { callback in
                    callback(ready, message)
                }
            }
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

            AppLogging.error(
                "Weryfikacja health helpera nieudana: \(details). Próba resetu połączenia XPC.",
                category: "Installation"
            )
            PrivilegedOperationClient.shared.resetConnectionForRecovery()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                PrivilegedOperationClient.shared.queryHealth { retryOK, retryDetails in
                    if retryOK {
                        completion(true, nil)
                        return
                    }

                    self.recoverRegistrationAfterHealthFailure(
                        interactive: interactive,
                        healthDetails: "\(details). Po resecie XPC: \(retryDetails)",
                        completion: completion
                    )
                }
            }
        }
    }

    private func recoverRegistrationAfterHealthFailure(
        interactive: Bool,
        healthDetails: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        coordinationQueue.async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            do {
                if service.status == .enabled {
                    try service.unregister()
                    Thread.sleep(forTimeInterval: 0.25)
                }

                try service.register()
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
            } catch {
                if service.status == .enabled {
                    AppLogging.info(
                        "Ponowna rejestracja helpera zwróciła błąd, ale status to enabled. Kontynuuję walidację.",
                        category: "Installation"
                    )
                    self.handlePostRegistrationStatus(interactive: interactive, completion: completion)
                    return
                }

                DispatchQueue.main.async {
                    self.presentRegistrationErrorAlertIfNeeded(error: error, interactive: interactive)
                }
                completion(
                    false,
                    "Helper nie odpowiada przez XPC (\(healthDetails)). Nie udało się ponownie zarejestrować helpera: \(error.localizedDescription)"
                )
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
