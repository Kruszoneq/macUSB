import Foundation
import AppKit
import ServiceManagement

extension HelperServiceManager {
    func repairRegistrationFromMenu() {
        guard markRepairStartIfPossible() else { return }
        if Thread.isMainThread {
            startRepairPresentation()
        } else {
            DispatchQueue.main.sync {
                self.startRepairPresentation()
            }
        }
        reportHelperServiceEvent("Rozpoczęto naprawę helpera z menu.")
        PrivilegedOperationClient.shared.resetConnectionForRecovery()
        reportHelperServiceEvent("Zresetowano lokalne połączenie XPC przed naprawą.")

        performFullRepairFromMenu { ready, message in
            self.finishRepairFlow()
            let summary = message ?? (ready
                                      ? String(localized: "Naprawa helpera zakończona")
                                      : String(localized: "Naprawa helpera zakończona błędem"))
            self.reportHelperServiceEvent("Naprawa helpera zakończona: \(ready ? "OK" : "BŁĄD"). Szczegóły: \(summary)")
            DispatchQueue.main.async {
                self.finishRepairPresentation(success: ready, message: summary)
            }
        }
    }
    func performFullRepairFromMenu(completion: @escaping EnsureCompletion) {
        reportHelperServiceEvent("Uruchamiam pełny reset helpera: unregister -> brak odpowiedzi starego -> register -> health-check.")

        guard isLocationRequirementSatisfied() else {
            let message = String(localized: "Aby uruchomić helper systemowy, aplikacja musi znajdować się w katalogu Applications.")
            reportHelperServiceEvent("Naprawa przerwana: warunek lokalizacji aplikacji niespełniony.")
            DispatchQueue.main.async {
                self.presentMoveToApplicationsAlert()
                completion(false, message)
            }
            return
        }

        coordinationQueue.async {
            if self.ensureInProgress {
                let message = String(localized: "Trwa inna operacja helpera. Poczekaj chwilę i spróbuj ponownie.")
                self.reportHelperServiceEvent("Naprawa przerwana: trwa równoległa operacja helpera.")
                DispatchQueue.main.async {
                    completion(false, message)
                }
                return
            }

            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            self.reportHelperServiceEvent("Status helpera przed resetem: \(self.statusDescription(service.status)).")

            self.performHardUnregisterPhase(service: service) { teardownOK, teardownMessage in
                guard teardownOK else {
                    DispatchQueue.main.async {
                        completion(false, teardownMessage ?? String(localized: "Nie udało się usunąć starej rejestracji helpera."))
                    }
                    return
                }
                self.performHardRegisterPhase(service: service, completion: completion)
            }
        }
    }
    func performHardUnregisterPhase(
        service: SMAppService,
        completion: @escaping (Bool, String?) -> Void
    ) {
        reportHelperServiceEvent("Wywołuję SMAppService.unregister() przed pełnym resetem helpera.")
        service.unregister { error in
            self.coordinationQueue.async {
                if let error {
                    self.reportHelperServiceEvent(
                        "SMAppService.unregister() zwróciło błąd: \(self.diagnosticErrorDescription(for: error)). Kontynuuję weryfikację teardown."
                    )
                } else {
                    self.reportHelperServiceEvent("SMAppService.unregister() zakończone.")
                }

                self.schedulePostUnregisterVerification(
                    service: service,
                    delaySeconds: 3.0,
                    allowExtendedDelay: true,
                    completion: completion
                )
            }
        }
    }
    func schedulePostUnregisterVerification(
        service: SMAppService,
        delaySeconds: TimeInterval,
        allowExtendedDelay: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let secondsText = Int(delaySeconds.rounded())
        reportHelperServiceEvent("Oczekiwanie \(secondsText) s po unregister na stabilizację usługi.")

        coordinationQueue.asyncAfter(deadline: .now() + delaySeconds) {
            let statusAfterUnregister = service.status
            self.reportHelperServiceEvent("Status helpera po unregister: \(self.statusDescription(statusAfterUnregister)).")

            if statusAfterUnregister == .enabled {
                if allowExtendedDelay {
                    self.reportHelperServiceEvent(
                        "Po 3 s brak zmiany statusu helpera (nadal aktywny). Dodaję dodatkowe 5 s przed kolejną próbą."
                    )
                    self.schedulePostUnregisterVerification(
                        service: service,
                        delaySeconds: 5.0,
                        allowExtendedDelay: false,
                        completion: completion
                    )
                    return
                }

                completion(false, String(localized: "Helper pozostał aktywny po unregister. Przerwano naprawę."))
                return
            }

            PrivilegedOperationClient.shared.resetConnectionForRecovery()
            self.reportHelperServiceEvent("Zresetowano połączenie XPC po unregister. Sprawdzam, czy stary helper przestał odpowiadać.")
            self.ensureOldHelperNoLongerResponds(
                attempt: 1,
                maxAttempts: 6,
                allowExtendedDelay: allowExtendedDelay,
                completion: completion
            )
        }
    }
    func ensureOldHelperNoLongerResponds(
        attempt: Int,
        maxAttempts: Int,
        allowExtendedDelay: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        PrivilegedOperationClient.shared.queryHealth(withTimeout: 0.7) { ok, details in
            self.coordinationQueue.async {
                if !ok {
                    self.reportHelperServiceEvent("Stary helper nie odpowiada po unregister (\(details)). Teardown zakończony.")
                    completion(true, nil)
                    return
                }

                if allowExtendedDelay, attempt == 1 {
                    self.reportHelperServiceEvent(
                        "Po 3 s brak zmiany odpowiedzi XPC (stary helper nadal odpowiada). Dodaję dodatkowe 5 s przed dalszą weryfikacją."
                    )
                    PrivilegedOperationClient.shared.resetConnectionForRecovery()
                    self.coordinationQueue.asyncAfter(deadline: .now() + 5.0) {
                        self.ensureOldHelperNoLongerResponds(
                            attempt: 1,
                            maxAttempts: maxAttempts,
                            allowExtendedDelay: false,
                            completion: completion
                        )
                    }
                    return
                }

                if attempt >= maxAttempts {
                    let message = "Po unregister stary helper nadal odpowiada przez XPC: \(details)"
                    self.reportHelperServiceEvent(message)
                    completion(false, message)
                    return
                }

                self.reportHelperServiceEvent("Stary helper nadal odpowiada (próba \(attempt)/\(maxAttempts)). Ponawiam teardown check.")
                PrivilegedOperationClient.shared.resetConnectionForRecovery()
                self.coordinationQueue.asyncAfter(deadline: .now() + 0.25) {
                    self.ensureOldHelperNoLongerResponds(
                        attempt: attempt + 1,
                        maxAttempts: maxAttempts,
                        allowExtendedDelay: false,
                        completion: completion
                    )
                }
            }
        }
    }
    func performHardRegisterPhase(
        service: SMAppService,
        completion: @escaping EnsureCompletion
    ) {
        coordinationQueue.asyncAfter(deadline: .now() + 0.3) {
            self.attemptHardRegister(service: service, attempt: 1, maxAttempts: 5, completion: completion)
        }
    }
    func attemptHardRegister(
        service: SMAppService,
        attempt: Int,
        maxAttempts: Int,
        completion: @escaping EnsureCompletion
    ) {
        reportHelperServiceEvent("Wywołuję SMAppService.register() po pełnym teardown (próba \(attempt)/\(maxAttempts)).")

        do {
            try service.register()
            reportHelperServiceEvent("SMAppService.register() po resecie zakończone bez błędu.")
        } catch {
            let details = diagnosticErrorDescription(for: error)
            reportHelperServiceEvent("SMAppService.register() po resecie zwróciło błąd: \(details)")

            let statusAfterError = service.status
            if statusAfterError == .enabled {
                reportHelperServiceEvent("Mimo błędu register() status helpera to enabled. Kontynuuję walidację.")
                finalizeHardRepairAfterSuccessfulRegister(service: service, completion: completion)
                return
            }

            guard attempt < maxAttempts, isRetryableHardRegisterError(error: error) else {
                DispatchQueue.main.async {
                    completion(false, details)
                }
                return
            }

            let retryDelay = hardRegisterRetryDelaySeconds(for: attempt)
            reportHelperServiceEvent("Retry register helpera za \(String(format: "%.2f", retryDelay)) s (próba \(attempt + 1)/\(maxAttempts)).")
            PrivilegedOperationClient.shared.resetConnectionForRecovery()

            coordinationQueue.asyncAfter(deadline: .now() + retryDelay) {
                self.attemptHardRegister(
                    service: service,
                    attempt: attempt + 1,
                    maxAttempts: maxAttempts,
                    completion: completion
                )
            }
            return
        }

        let statusAfterRegister = service.status
        reportHelperServiceEvent("Status helpera po rejestracji: \(statusDescription(statusAfterRegister)).")

        guard statusAfterRegister == .enabled else {
            if attempt < maxAttempts, statusAfterRegister == .notRegistered || statusAfterRegister == .notFound {
                let retryDelay = hardRegisterRetryDelaySeconds(for: attempt)
                reportHelperServiceEvent("Status po register to \(statusDescription(statusAfterRegister)). Ponawiam próbę za \(String(format: "%.2f", retryDelay)) s.")
                PrivilegedOperationClient.shared.resetConnectionForRecovery()
                coordinationQueue.asyncAfter(deadline: .now() + retryDelay) {
                    self.attemptHardRegister(
                        service: service,
                        attempt: attempt + 1,
                        maxAttempts: maxAttempts,
                        completion: completion
                    )
                }
                return
            }

            let message: String
            if statusAfterRegister == .requiresApproval {
                message = String(localized: "Helper został zarejestrowany, ale wymaga zatwierdzenia przez użytkownika.")
            } else {
                message = String(localized: "Nie udało się aktywować helpera po pełnym resecie.")
            }
            DispatchQueue.main.async {
                completion(false, message)
            }
            return
        }

        finalizeHardRepairAfterSuccessfulRegister(service: service, completion: completion)
    }
    func finalizeHardRepairAfterSuccessfulRegister(
        service: SMAppService,
        completion: @escaping EnsureCompletion
    ) {
        coordinationQueue.asyncAfter(deadline: .now() + 0.3) {
            PrivilegedOperationClient.shared.resetConnectionForRecovery()
            self.reportHelperServiceEvent("Ponownie zresetowano połączenie XPC po rejestracji.")
            self.attemptHardRepairHealthValidation(
                service: service,
                attempt: 1,
                maxAttempts: 4,
                completion: completion
            )
        }
    }
    func attemptHardRepairHealthValidation(
        service: SMAppService,
        attempt: Int,
        maxAttempts: Int,
        completion: @escaping EnsureCompletion
    ) {
        PrivilegedOperationClient.shared.queryHealth(withTimeout: 2.4) { ok, details in
            self.coordinationQueue.async {
                let finalStatus = service.status
                if ok, finalStatus == .enabled {
                    self.reportHelperServiceEvent("Pełna naprawa helpera zakończona sukcesem. Health XPC: \(details).")
                    DispatchQueue.main.async {
                        completion(true, nil)
                    }
                    return
                }

                if attempt < maxAttempts {
                    let retryDelay = 0.35 * Double(attempt)
                    self.reportHelperServiceEvent(
                        "Health-check helpera niegotowy (próba \(attempt)/\(maxAttempts)): status=\(self.statusDescription(finalStatus)), details=\(details). Ponawiam za \(String(format: "%.2f", retryDelay)) s."
                    )
                    PrivilegedOperationClient.shared.resetConnectionForRecovery()
                    self.coordinationQueue.asyncAfter(deadline: .now() + retryDelay) {
                        self.attemptHardRepairHealthValidation(
                            service: service,
                            attempt: attempt + 1,
                            maxAttempts: maxAttempts,
                            completion: completion
                        )
                    }
                    return
                }

                let message = "Helper po pełnym resecie nadal nie jest gotowy. Status: \(self.statusDescription(finalStatus)). Szczegóły XPC: \(details)"
                self.reportHelperServiceEvent(message)
                DispatchQueue.main.async {
                    completion(false, message)
                }
            }
        }
    }
    func isRetryableHardRegisterError(error: Error) -> Bool {
        if isOperationNotPermitted(error) || isLikelyBackgroundTaskPolicyBlock(error) {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == 4099 {
            return true
        }

        let lowered = nsError.localizedDescription.lowercased()
        if lowered.contains("operation not permitted")
            || lowered.contains("temporarily unavailable")
            || lowered.contains("interrupted")
        {
            return true
        }
        return false
    }
    func hardRegisterRetryDelaySeconds(for attempt: Int) -> TimeInterval {
        switch attempt {
        case 1: return 0.4
        case 2: return 0.8
        case 3: return 1.6
        default: return 2.2
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
}
