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
        reportHelperRepairEvent("Manual helper repair started from the Tools menu.")
        PrivilegedOperationClient.shared.resetConnectionForRecovery()
        reportHelperRepairEvent("Reset the local XPC connection before repair.")

        performFullRepairFromMenu { ready, message in
            self.finishRepairFlow()
            let summary = message ?? (ready
                                      ? String(localized: "Naprawa helpera zakończona")
                                      : String(localized: "Naprawa helpera zakończona błędem"))
            self.reportHelperRepairEvent("Manual helper repair finished: success=\(ready).", isError: !ready)
            DispatchQueue.main.async {
                self.finishRepairPresentation(success: ready, message: summary)
            }
        }
    }
    func performFullRepairFromMenu(completion: @escaping EnsureCompletion) {
        let operationToken = AppActiveOperationRegistry.shared.begin(
            kind: .helperRepair,
            context: "helper_full_repair",
            logStage: .helper,
            logWorkflow: .repair
        )
        let trackedCompletion: EnsureCompletion = { ready, message in
            operationToken.finish()
            completion(ready, message)
        }
        reportHelperRepairEvent("Starting full helper reset: unregister, verify old service shutdown, register, then check XPC health.")

        guard isLocationRequirementSatisfied() else {
            let message = String(localized: "Aby uruchomić helper systemowy, aplikacja musi znajdować się w katalogu Applications.")
            reportHelperRepairEvent("Repair stopped: application location requirement not met.", isError: true)
            DispatchQueue.main.async {
                self.presentMoveToApplicationsAlert()
                trackedCompletion(false, message)
            }
            return
        }

        coordinationQueue.async {
            if self.ensureInProgress {
                let message = String(localized: "Trwa inna operacja helpera. Poczekaj chwilę i spróbuj ponownie.")
                self.reportHelperRepairEvent("Repair stopped: another helper operation is active.", isError: true)
                DispatchQueue.main.async {
                    trackedCompletion(false, message)
                }
                return
            }

            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            self.reportHelperRepairEvent("Helper status before reset: \(self.diagnosticStatusDescription(service.status)).")

            self.performHardUnregisterPhase(service: service) { teardownOK, teardownMessage in
                guard teardownOK else {
                    DispatchQueue.main.async {
                        trackedCompletion(false, teardownMessage ?? String(localized: "Nie udało się usunąć starej rejestracji helpera."))
                    }
                    return
                }
                self.performHardRegisterPhase(service: service, completion: trackedCompletion)
            }
        }
    }
    func performHardUnregisterPhase(
        service: SMAppService,
        completion: @escaping (Bool, String?) -> Void
    ) {
        reportHelperRepairEvent("Calling SMAppService.unregister() before the full helper reset.")
        service.unregister { error in
            self.coordinationQueue.async {
                if let error {
                    self.reportHelperRepairEvent(
                        "SMAppService.unregister() returned an error: \(self.diagnosticErrorDescription(for: error)). Continuing shutdown verification.",
                        isError: true
                    )
                } else {
                    self.reportHelperRepairEvent("SMAppService.unregister() completed.")
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
        reportHelperRepairEvent("Waiting \(secondsText) s after unregister for service stabilization.")

        coordinationQueue.asyncAfter(deadline: .now() + delaySeconds) {
            let statusAfterUnregister = service.status
            self.reportHelperRepairEvent("Helper status after unregister: \(self.diagnosticStatusDescription(statusAfterUnregister)).")

            if statusAfterUnregister == .enabled {
                if allowExtendedDelay {
                    self.reportHelperRepairEvent(
                        "Helper status is still enabled after 3 s. Waiting another 5 s before retrying."
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
            self.reportHelperRepairEvent("Reset the XPC connection after unregister; checking whether the old helper has stopped responding.")
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
                    self.reportHelperRepairEvent("Old helper no longer responds after unregister: \(details). Shutdown verified.")
                    completion(true, nil)
                    return
                }

                if allowExtendedDelay, attempt == 1 {
                    self.reportHelperRepairEvent(
                        "Old helper still responds over XPC after 3 s. Waiting another 5 s before retrying."
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
                    self.reportHelperRepairEvent("Old helper still responds over XPC after unregister: \(details).", isError: true)
                    completion(false, message)
                    return
                }

                self.reportHelperRepairEvent("Old helper still responds (attempt \(attempt)/\(maxAttempts)); retrying shutdown verification.")
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
        reportHelperRepairEvent("Calling SMAppService.register() after shutdown (attempt \(attempt)/\(maxAttempts)).")

        do {
            try service.register()
            reportHelperRepairEvent("SMAppService.register() completed without an error.")
        } catch {
            let details = diagnosticErrorDescription(for: error)
            reportHelperRepairEvent("SMAppService.register() returned an error: \(details)", isError: true)

            let statusAfterError = service.status
            if statusAfterError == .enabled {
                reportHelperRepairEvent("Helper status is enabled despite the register() error; continuing validation.")
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
            reportHelperRepairEvent("Retrying helper registration in \(String(format: "%.2f", retryDelay)) s (attempt \(attempt + 1)/\(maxAttempts)).")
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
        reportHelperRepairEvent("Helper status after registration: \(diagnosticStatusDescription(statusAfterRegister)).")

        guard statusAfterRegister == .enabled else {
            if attempt < maxAttempts, statusAfterRegister == .notRegistered || statusAfterRegister == .notFound {
                let retryDelay = hardRegisterRetryDelaySeconds(for: attempt)
                reportHelperRepairEvent("Helper status after register() is \(diagnosticStatusDescription(statusAfterRegister)); retrying in \(String(format: "%.2f", retryDelay)) s.")
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
            self.reportHelperRepairEvent("Reset the XPC connection after registration.")
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
        PrivilegedOperationClient.shared.queryHealth(
            withTimeout: 2.4,
            presentsTrustFailureAlert: true
        ) { ok, details in
            self.coordinationQueue.async {
                let finalStatus = service.status
                if ok, finalStatus == .enabled {
                    self.reportHelperRepairEvent("Full helper repair succeeded. XPC health: \(details).")
                    DispatchQueue.main.async {
                        completion(true, nil)
                    }
                    return
                }

                if attempt < maxAttempts {
                    let retryDelay = 0.35 * Double(attempt)
                    self.reportHelperRepairEvent(
                        "Helper XPC health check not ready (attempt \(attempt)/\(maxAttempts)): status=\(self.diagnosticStatusDescription(finalStatus)), details=\(details). Retrying in \(String(format: "%.2f", retryDelay)) s."
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
                self.reportHelperRepairEvent(
                    "Helper is still not ready after full reset: status=\(self.diagnosticStatusDescription(finalStatus)), XPC details=\(details).",
                    isError: true
                )
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
