import Foundation
import AppKit
import ServiceManagement

extension HelperServiceManager {
    func reportHelperReadinessEvent(_ message: String, isError: Bool = false) {
        reportHelperServiceEvent(message, stage: .helper, isError: isError)
    }

    func ensureReadyForPrivilegedWork(completion: @escaping (Bool, String?) -> Void) {
        ensureReadyForPrivilegedWork(interactive: true, completion: completion)
    }

    func forceReloadForIPCContractMismatch(completion: @escaping (Bool, String?) -> Void) {
        reportHelperReadinessEvent("Potential helper IPC contract mismatch detected; forcing a service reload.")
        coordinationQueue.async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            PrivilegedOperationClient.shared.resetConnectionForRecovery()

            do {
                switch service.status {
                case .enabled, .requiresApproval:
                    do {
                        try service.unregister()
                        self.reportHelperReadinessEvent("Helper unregistered before forced reload.")
                    } catch {
                        self.reportHelperReadinessEvent("Could not unregister helper before reload: \(error.localizedDescription)")
                    }
                    Thread.sleep(forTimeInterval: 0.3)
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    break
                }

                try service.register()
                self.reportHelperReadinessEvent("Helper re-registered after IPC mismatch.")

                self.handlePostRegistrationStatus(interactive: true) { ready, message in
                    if ready {
                        PrivilegedOperationClient.shared.resetConnectionForRecovery()
                    }
                    DispatchQueue.main.async {
                        completion(ready, message)
                    }
                }
            } catch {
                self.reportHelperReadinessEvent("Forced helper reload failed: \(error.localizedDescription)")
                let fallback = String(localized: "Nie udało się automatycznie odświeżyć helpera. Otwórz Narzędzia → Napraw helpera i spróbuj ponownie.")
                let mergedMessage = "\(fallback) (\(error.localizedDescription))"
                DispatchQueue.main.async {
                    completion(false, mergedMessage)
                }
            }
        }
    }
    func ensureReadyForPrivilegedWork(interactive: Bool, completion: @escaping (Bool, String?) -> Void) {
        reportHelperReadinessEvent("Checking helper startup requirements (interactive=\(interactive ? "yes" : "no")).")
        guard isLocationRequirementSatisfied() else {
            let message = String(localized: "Aby uruchomić helper systemowy, aplikacja musi znajdować się w katalogu Applications.")
            reportHelperReadinessEvent("Application location requirement not met.")
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
            self.reportHelperReadinessEvent("Helper readiness request queued (interactive=\(interactive ? "yes" : "no")).")

            guard !self.ensureInProgress else {
                AppLogging.info(
                    "Concurrent helper readiness request detected; joining the current operation.",
                    stage: .helper
                )
                self.reportHelperReadinessEvent("Joined the current helper readiness operation.")
                return
            }

            self.ensureInProgress = true
            let runInteractive = self.pendingEnsureInteractive
            self.reportHelperReadinessEvent("Starting helper readiness flow (interactive=\(runInteractive ? "yes" : "no")).")
            self.runEnsureFlow(interactive: runInteractive)
        }
    }
    func runEnsureFlow(interactive: Bool) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        reportHelperReadinessEvent("Current SMAppService status: \(diagnosticStatusDescription(service.status)).")
        switch service.status {
        case .enabled:
            reportHelperReadinessEvent(
                "Helper service is enabled; checking XPC health."
            )
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: true) { ready, message in
                self.finalizeEnsureRequests(ready: ready, message: message)
            }

        case .requiresApproval:
            reportHelperReadinessEvent("Helper requires approval in System Settings.")
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
            reportHelperReadinessEvent("Helper is not registered; starting registration.")
            registerAndValidate(interactive: interactive) { ready, message in
                self.finalizeEnsureRequests(ready: ready, message: message)
            }

        @unknown default:
            reportHelperReadinessEvent("Unknown helper status detected.")
            finalizeEnsureRequests(ready: false, message: String(localized: "Nieznany status helpera."))
        }
    }
    func registerAndValidate(interactive: Bool, completion: @escaping EnsureCompletion) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        do {
            reportHelperReadinessEvent("Calling SMAppService.register().")
            try service.register()
            reportHelperReadinessEvent("SMAppService.register() completed without error.")
            handlePostRegistrationStatus(interactive: interactive, completion: completion)
        } catch {
            reportHelperReadinessEvent("SMAppService.register() returned an error: \(error.localizedDescription)")
            if service.status == .enabled {
                AppLogging.info(
                    "register() returned an error, but helper status is enabled; continuing validation.",
                    stage: .helper
                )
                reportHelperReadinessEvent("Helper status is enabled despite register() error; continuing validation.")
                handlePostRegistrationStatus(interactive: interactive, completion: completion)
                return
            }

            if isLikelyBackgroundTaskPolicyBlock(error) {
                let details = diagnosticErrorDescription(for: error)
                let guidance = String(localized: "System blokuje rejestrację helpera (Background Task Management). Usuń stare wpisy macUSB z „Login Items / Allow in the Background”, uruchom `sudo sfltool resetbtm`, uruchom ponownie macOS i uruchom tylko wersję z /Applications.")
                reportHelperReadinessEvent("BTM block detected during register(): \(details)")
                completion(false, "\(guidance) Szczegóły: \(details)")
                return
            }

            if isRunningFromXcodeSession() && isOperationNotPermitted(error) {
                AppLogging.error(
                    "System blocked helper registration from Xcode (Operation not permitted).",
                    stage: .helper
                )
                PrivilegedOperationClient.shared.queryHealth(
                    withTimeout: 1.2,
                    presentsTrustFailureAlert: interactive
                ) { ok, details in
                    if ok {
                        let identity = PrivilegedOperationClient.shared.diagnosticHealthIdentity(from: details)
                        self.reportHelperReadinessEvent(
                            "XPC health check passed after registration error\(identity.map { " \($0)" } ?? "")."
                        )
                        completion(true, nil)
                        return
                    }

                    self.reportHelperReadinessEvent(
                        "XPC health check failed after registration error.",
                        isError: true
                    )
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
        reportHelperReadinessEvent("Helper readiness flow completed: \(ready ? "OK" : "FAILED").")
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
        reportHelperReadinessEvent("Helper status after registration: \(diagnosticStatusDescription(service.status)).")
        switch service.status {
        case .enabled:
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: false, completion: completion)
        case .requiresApproval:
            reportHelperReadinessEvent("Helper requires user approval after registration.")
            if interactive {
                presentApprovalRequiredAlert()
            }
            completion(false, String(localized: "Helper został zarejestrowany, ale wymaga zatwierdzenia przez użytkownika."))
        case .notRegistered, .notFound:
            reportHelperReadinessEvent("Helper is still inactive after registration.")
            completion(false, String(localized: "Nie udało się aktywować helpera."))
        @unknown default:
            reportHelperReadinessEvent("Unknown helper status after registration.")
            completion(false, String(localized: "Nieznany status helpera po rejestracji."))
        }
    }
    func validateEnabledServiceHealth(
        interactive: Bool,
        allowRecovery: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        reportHelperReadinessEvent("XPC health check started.")
        PrivilegedOperationClient.shared.queryHealth(
            withTimeout: 5,
            presentsTrustFailureAlert: interactive
        ) { ok, details in
            if ok {
                let identity = PrivilegedOperationClient.shared.diagnosticHealthIdentity(from: details)
                self.reportHelperReadinessEvent(
                    "XPC health check passed\(identity.map { " \($0)" } ?? "")."
                )
                completion(true, nil)
                return
            }
            self.reportHelperReadinessEvent("XPC health check failed.", isError: true)

            guard allowRecovery else {
                completion(false, "Helper jest włączony, ale XPC nie odpowiada: \(details)")
                return
            }

            PrivilegedOperationClient.shared.resetConnectionForRecovery()
            self.reportHelperReadinessEvent(
                "XPC connection reset; retrying the health check."
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                PrivilegedOperationClient.shared.queryHealth(
                    withTimeout: 5,
                    presentsTrustFailureAlert: interactive
                ) { retryOK, retryDetails in
                    if retryOK {
                        let identity = PrivilegedOperationClient.shared.diagnosticHealthIdentity(from: retryDetails)
                        self.reportHelperReadinessEvent(
                            "XPC health check passed after connection reset\(identity.map { " \($0)" } ?? "")."
                        )
                        completion(true, nil)
                        return
                    }
                    self.reportHelperReadinessEvent(
                        "XPC health check failed after connection reset.",
                        isError: true
                    )

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
        reportHelperReadinessEvent("Starting helper registration recovery.")
        coordinationQueue.async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            self.reportHelperReadinessEvent("Helper status before recovery: \(self.diagnosticStatusDescription(service.status)).")

            let registerAfterRecovery: () -> Void = {
                self.reportHelperReadinessEvent("Calling register() during recovery.")
                do {
                    try service.register()
                    self.reportHelperReadinessEvent("Helper status after recovery register(): \(self.diagnosticStatusDescription(service.status)).")
                    self.handlePostRegistrationStatus(interactive: interactive) { ready, message in
                        guard ready else {
                            self.reportHelperReadinessEvent("Helper is still not ready after recovery register().")
                            completion(false, message)
                            return
                        }

                        PrivilegedOperationClient.shared.queryHealth(
                            withTimeout: 5,
                            presentsTrustFailureAlert: interactive
                        ) { recovered, recoveredDetails in
                            if recovered {
                                let identity = PrivilegedOperationClient.shared.diagnosticHealthIdentity(from: recoveredDetails)
                                self.reportHelperReadinessEvent(
                                    "XPC health check passed after registration recovery\(identity.map { " \($0)" } ?? "")."
                                )
                                completion(true, nil)
                            } else {
                                self.reportHelperReadinessEvent(
                                    "XPC health check failed after registration recovery.",
                                    isError: true
                                )
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

            self.reportHelperReadinessEvent("Helper is enabled; calling unregister() before re-registration.")
            service.unregister { error in
                self.coordinationQueue.async {
                    if let error {
                        self.reportHelperReadinessEvent(
                            "Recovery unregister() returned an error: \(self.diagnosticErrorDescription(for: error)). Helper status after error: \(self.diagnosticStatusDescription(service.status))."
                        )
                    } else {
                        self.reportHelperReadinessEvent("Recovery unregister() completed. Helper status: \(self.diagnosticStatusDescription(service.status)).")
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
        reportHelperReadinessEvent("Helper recovery failed: \(diagnosticErrorDescription(for: error))")
        if service.status == .enabled {
            AppLogging.info(
                "Helper re-registration returned an error, but status is enabled; continuing validation.",
                stage: .helper
            )
            reportHelperReadinessEvent("Helper status is enabled despite recovery error; continuing validation.")
            handlePostRegistrationStatus(interactive: interactive, completion: completion)
            return
        }

        if isRunningFromXcodeSession() && isOperationNotPermitted(error) {
            PrivilegedOperationClient.shared.queryHealth(
                withTimeout: 1.2,
                presentsTrustFailureAlert: interactive
            ) { ok, details in
                if ok {
                    self.reportHelperReadinessEvent("Recovery blocked in Xcode session, but helper responds over XPC.")
                    completion(true, nil)
                    return
                }

                self.reportHelperReadinessEvent("Recovery blocked in Xcode session and helper still does not respond over XPC.")
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
