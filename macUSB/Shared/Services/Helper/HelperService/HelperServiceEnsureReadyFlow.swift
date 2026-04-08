import Foundation
import AppKit
import ServiceManagement

extension HelperServiceManager {
    func ensureReadyForPrivilegedWork(completion: @escaping (Bool, String?) -> Void) {
        ensureReadyForPrivilegedWork(interactive: true, completion: completion)
    }

    func forceReloadForIPCContractMismatch(completion: @escaping (Bool, String?) -> Void) {
        reportHelperServiceEvent("Wykryto potencjalną niezgodność kontraktu IPC helpera. Wymuszam przeładowanie usługi.")
        coordinationQueue.async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            PrivilegedOperationClient.shared.resetConnectionForRecovery()

            do {
                switch service.status {
                case .enabled, .requiresApproval:
                    do {
                        try service.unregister()
                        self.reportHelperServiceEvent("Helper wyrejestrowany przed wymuszonym przeładowaniem.")
                    } catch {
                        self.reportHelperServiceEvent("Nie udało się wyrejestrować helpera przed przeładowaniem: \(error.localizedDescription)")
                    }
                    Thread.sleep(forTimeInterval: 0.3)
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    break
                }

                try service.register()
                self.reportHelperServiceEvent("Helper ponownie zarejestrowany po wykryciu niezgodności IPC.")

                self.handlePostRegistrationStatus(interactive: true) { ready, message in
                    if ready {
                        PrivilegedOperationClient.shared.resetConnectionForRecovery()
                    }
                    DispatchQueue.main.async {
                        completion(ready, message)
                    }
                }
            } catch {
                self.reportHelperServiceEvent("Wymuszone przeładowanie helpera nieudane: \(error.localizedDescription)")
                let fallback = String(localized: "Nie udało się automatycznie odświeżyć helpera. Otwórz Narzędzia → Napraw helpera i spróbuj ponownie.")
                let mergedMessage = "\(fallback) (\(error.localizedDescription))"
                DispatchQueue.main.async {
                    completion(false, mergedMessage)
                }
            }
        }
    }
    func ensureReadyForPrivilegedWork(interactive: Bool, completion: @escaping (Bool, String?) -> Void) {
        reportHelperServiceEvent("Sprawdzanie warunków startu helpera (interactive=\(interactive ? "TAK" : "NIE")).")
        guard isLocationRequirementSatisfied() else {
            let message = String(localized: "Aby uruchomić helper systemowy, aplikacja musi znajdować się w katalogu Applications.")
            reportHelperServiceEvent("Warunek lokalizacji aplikacji niespełniony.")
            if interactive {
                presentMoveToApplicationsAlert()
            }
            completion(false, message)
            return
        }

        queueEnsureRequest(interactive: interactive, completion: completion)
    }
    func queueEnsureRequest(interactive: Bool, completion: @escaping EnsureCompletion) {
        coordinationQueue.async {
            self.pendingEnsureCompletions.append(completion)
            self.pendingEnsureInteractive = self.pendingEnsureInteractive || interactive
            self.reportHelperServiceEvent("Dodano żądanie gotowości helpera (interactive=\(interactive ? "TAK" : "NIE")).")

            guard !self.ensureInProgress else {
                AppLogging.info(
                    "Wykryto równoległe żądanie gotowości helpera - dołączam do trwającej operacji.",
                    category: "Installation"
                )
                self.reportHelperServiceEvent("Dołączono do trwającej operacji gotowości helpera.")
                return
            }

            self.ensureInProgress = true
            let runInteractive = self.pendingEnsureInteractive
            self.reportHelperServiceEvent("Rozpoczynam flow gotowości helpera (interactive=\(runInteractive ? "TAK" : "NIE")).")
            self.runEnsureFlow(interactive: runInteractive)
        }
    }
    func runEnsureFlow(interactive: Bool) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        reportHelperServiceEvent("Aktualny status SMAppService: \(statusDescription(service.status)).")
        switch service.status {
        case .enabled:
            reportHelperServiceEvent("Helper jest oznaczony jako włączony. Weryfikuję health XPC.")
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: true) { ready, message in
                self.finalizeEnsureRequests(ready: ready, message: message)
            }

        case .requiresApproval:
            reportHelperServiceEvent("Helper wymaga zatwierdzenia w Ustawieniach systemowych.")
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
            reportHelperServiceEvent("Helper nie jest zarejestrowany. Rozpoczynam rejestrację.")
            registerAndValidate(interactive: interactive) { ready, message in
                self.finalizeEnsureRequests(ready: ready, message: message)
            }

        @unknown default:
            reportHelperServiceEvent("Wykryto nieznany status helpera.")
            finalizeEnsureRequests(ready: false, message: String(localized: "Nieznany status helpera."))
        }
    }
    func registerAndValidate(interactive: Bool, completion: @escaping EnsureCompletion) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        do {
            reportHelperServiceEvent("Wywołuję SMAppService.register().")
            try service.register()
            reportHelperServiceEvent("SMAppService.register() zakończone bez błędu.")
            handlePostRegistrationStatus(interactive: interactive, completion: completion)
        } catch {
            reportHelperServiceEvent("SMAppService.register() zwróciło błąd: \(error.localizedDescription)")
            if service.status == .enabled {
                AppLogging.info(
                    "register() zwrócił błąd, ale helper jest oznaczony jako enabled. Kontynuuję walidację.",
                    category: "Installation"
                )
                reportHelperServiceEvent("Mimo błędu register() status helpera to enabled. Kontynuuję walidację.")
                handlePostRegistrationStatus(interactive: interactive, completion: completion)
                return
            }

            if isLikelyBackgroundTaskPolicyBlock(error) {
                let details = diagnosticErrorDescription(for: error)
                let guidance = String(localized: "System blokuje rejestrację helpera (Background Task Management). Usuń stare wpisy macUSB z „Login Items / Allow in the Background”, uruchom `sudo sfltool resetbtm`, uruchom ponownie macOS i uruchom tylko wersję z /Applications.")
                reportHelperServiceEvent("Wykryto blokadę BTM podczas register(): \(details)")
                completion(false, "\(guidance) Szczegóły: \(details)")
                return
            }

            if isRunningFromXcodeSession() && isOperationNotPermitted(error) {
                AppLogging.error(
                    "Rejestracja helpera z uruchomienia Xcode została zablokowana przez system (Operation not permitted).",
                    category: "Installation"
                )
                PrivilegedOperationClient.shared.queryHealth(withTimeout: 1.2) { ok, details in
                    if ok {
                        self.reportHelperServiceEvent("Health XPC po błędzie register() jest poprawny.")
                        completion(true, nil)
                        return
                    }

                    self.reportHelperServiceEvent("Health XPC po błędzie register() nadal nie działa: \(details)")
                    completion(
                        false,
                        String(localized: "System zablokował rejestrację helpera z uruchomienia Xcode. Uruchom raz aplikację z katalogu Applications, zatwierdź działanie helpera w tle, a następnie wróć do testów w Xcode. Szczegóły XPC: \(details)")
                    )
                }
                return
            }

            DispatchQueue.main.async {
                self.presentRegistrationErrorAlertIfNeeded(error: error, interactive: interactive)
            }
            completion(false, error.localizedDescription)
        }
    }
    func finalizeEnsureRequests(ready: Bool, message: String?) {
        reportHelperServiceEvent("Flow gotowości helpera zakończony: \(ready ? "OK" : "BŁĄD").")
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
    func handlePostRegistrationStatus(interactive: Bool, completion: @escaping (Bool, String?) -> Void) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        reportHelperServiceEvent("Status helpera po rejestracji: \(statusDescription(service.status)).")
        switch service.status {
        case .enabled:
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: false, completion: completion)
        case .requiresApproval:
            reportHelperServiceEvent("Helper po rejestracji wymaga zatwierdzenia użytkownika.")
            if interactive {
                presentApprovalRequiredAlert()
            }
            completion(false, String(localized: "Helper został zarejestrowany, ale wymaga zatwierdzenia przez użytkownika."))
        case .notRegistered, .notFound:
            reportHelperServiceEvent("Po rejestracji helper nadal nie jest aktywny.")
            completion(false, String(localized: "Nie udało się aktywować helpera."))
        @unknown default:
            reportHelperServiceEvent("Nieznany status helpera po rejestracji.")
            completion(false, String(localized: "Nieznany status helpera po rejestracji."))
        }
    }
    func validateEnabledServiceHealth(
        interactive: Bool,
        allowRecovery: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        reportHelperServiceEvent("Rozpoczynam weryfikację health XPC helpera.")
        PrivilegedOperationClient.shared.queryHealth { ok, details in
            if ok {
                self.reportHelperServiceEvent("Health XPC: OK (\(details)).")
                completion(true, nil)
                return
            }
            self.reportHelperServiceEvent("Health XPC: BŁĄD (\(details)).")

            guard allowRecovery else {
                completion(false, "Helper jest włączony, ale XPC nie odpowiada: \(details)")
                return
            }

            AppLogging.error(
                "Weryfikacja health helpera nieudana: \(details). Próba resetu połączenia XPC.",
                category: "Installation"
            )
            PrivilegedOperationClient.shared.resetConnectionForRecovery()
            self.reportHelperServiceEvent("Zresetowano połączenie XPC. Ponawiam health-check.")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                PrivilegedOperationClient.shared.queryHealth { retryOK, retryDetails in
                    if retryOK {
                        self.reportHelperServiceEvent("Health XPC po resecie: OK (\(retryDetails)).")
                        completion(true, nil)
                        return
                    }
                    self.reportHelperServiceEvent("Health XPC po resecie nadal nie działa: \(retryDetails).")

                    self.recoverRegistrationAfterHealthFailure(
                        interactive: interactive,
                        healthDetails: "\(details). Po resecie XPC: \(retryDetails)",
                        completion: completion
                    )
                }
            }
        }
    }
    func recoverRegistrationAfterHealthFailure(
        interactive: Bool,
        healthDetails: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        reportHelperServiceEvent("Uruchamiam procedurę odzyskiwania rejestracji helpera.")
        coordinationQueue.async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            self.reportHelperServiceEvent("Status helpera przed recover: \(self.statusDescription(service.status)).")

            let registerAfterRecovery: () -> Void = {
                self.reportHelperServiceEvent("Wywołuję register() po odzyskiwaniu.")
                do {
                    try service.register()
                    self.reportHelperServiceEvent("Status helpera po register() w recover: \(self.statusDescription(service.status)).")
                    self.handlePostRegistrationStatus(interactive: interactive) { ready, message in
                        guard ready else {
                            self.reportHelperServiceEvent("Po recover register() helper nadal nie jest gotowy.")
                            completion(false, message)
                            return
                        }

                        PrivilegedOperationClient.shared.queryHealth { recovered, recoveredDetails in
                            if recovered {
                                self.reportHelperServiceEvent("Health XPC po odzyskiwaniu: OK (\(recoveredDetails)).")
                                completion(true, nil)
                            } else {
                                self.reportHelperServiceEvent("Health XPC po odzyskiwaniu nadal nie działa: \(recoveredDetails).")
                                completion(
                                    false,
                                    "Helper został ponownie zarejestrowany, ale XPC nadal nie działa: \(recoveredDetails). Poprzedni błąd: \(healthDetails)"
                                )
                            }
                        }
                    }
                } catch {
                    self.handleRecoveryRegistrationError(
                        service: service,
                        error: error,
                        interactive: interactive,
                        healthDetails: healthDetails,
                        completion: completion
                    )
                }
            }

            guard service.status == .enabled else {
                registerAfterRecovery()
                return
            }

            self.reportHelperServiceEvent("Helper jest enabled. Wywołuję unregister() przed ponowną rejestracją.")
            service.unregister { error in
                self.coordinationQueue.async {
                    if let error {
                        self.reportHelperServiceEvent(
                            "unregister() w recover zwróciło błąd: \(self.diagnosticErrorDescription(for: error)). Status helpera po błędzie: \(self.statusDescription(service.status))."
                        )
                    } else {
                        self.reportHelperServiceEvent("unregister() w recover zakończone. Status helpera: \(self.statusDescription(service.status)).")
                    }

                    self.coordinationQueue.asyncAfter(deadline: .now() + 0.15) {
                        registerAfterRecovery()
                    }
                }
            }
        }
    }
    func handleRecoveryRegistrationError(
        service: SMAppService,
        error: Error,
        interactive: Bool,
        healthDetails: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        reportHelperServiceEvent("Błąd podczas odzyskiwania helpera: \(diagnosticErrorDescription(for: error))")
        if service.status == .enabled {
            AppLogging.info(
                "Ponowna rejestracja helpera zwróciła błąd, ale status to enabled. Kontynuuję walidację.",
                category: "Installation"
            )
            reportHelperServiceEvent("Mimo błędu recover status helpera to enabled. Kontynuuję walidację.")
            handlePostRegistrationStatus(interactive: interactive, completion: completion)
            return
        }

        if isRunningFromXcodeSession() && isOperationNotPermitted(error) {
            PrivilegedOperationClient.shared.queryHealth(withTimeout: 1.2) { ok, details in
                if ok {
                    self.reportHelperServiceEvent("W sesji Xcode recovery zablokowany, ale helper odpowiada przez XPC.")
                    completion(true, nil)
                    return
                }

                self.reportHelperServiceEvent("W sesji Xcode recovery zablokowany i helper nadal nie odpowiada przez XPC.")
                completion(
                    false,
                    "System zablokował ponowną rejestrację helpera z sesji Xcode. Uruchom aplikację z katalogu /Applications i wykonaj naprawę helpera. Szczegóły XPC: \(details). Poprzedni błąd: \(healthDetails)"
                )
            }
            return
        }

        if isLikelyBackgroundTaskPolicyBlock(error) {
            let details = diagnosticErrorDescription(for: error)
            completion(
                false,
                "System blokuje ponowną rejestrację helpera (Background Task Management). Usuń stare wpisy macUSB z „Login Items / Allow in the Background”, uruchom `sudo sfltool resetbtm`, uruchom ponownie macOS i uruchom tylko wersję z /Applications. Szczegóły: \(details)"
            )
            return
        }

        DispatchQueue.main.async {
            self.presentRegistrationErrorAlertIfNeeded(error: error, interactive: interactive)
        }
        completion(
            false,
            "Helper nie odpowiada przez XPC (\(healthDetails)). Nie udało się ponownie zarejestrować helpera: \(diagnosticErrorDescription(for: error))"
        )
    }
}
