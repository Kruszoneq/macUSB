import Foundation
import AppKit
import ServiceManagement

extension HelperServiceManager {
    private enum StartupAutoRepairDecision {
        case noRepairNeeded
        case needsRepair(previousFingerprint: String?)
    }

    func bootstrapIfNeededAtStartup(completion: @escaping (Bool) -> Void) {
        refreshBackgroundApprovalState()
        let startupDecision = startupAutoRepairDecision()

        #if DEBUG
        if Self.isRunningFromXcodeDevelopmentBuild() {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            if service.status == .requiresApproval {
                presentStartupApprovalAlertIfNeeded {
                    completion(false)
                }
            } else {
                runStartupAutoRepairIfNeeded(decision: startupDecision) { autoRepairOK in
                    completion(autoRepairOK)
                }
            }
            return
        }
        #endif

        ensureReadyForPrivilegedWork(interactive: false) { ready, _ in
            guard ready else {
                self.presentStartupApprovalAlertIfNeeded {
                    completion(false)
                }
                return
            }

            self.runStartupAutoRepairIfNeeded(decision: startupDecision) { autoRepairOK in
                completion(autoRepairOK)
            }
        }
    }

    private func runStartupAutoRepairIfNeeded(
        decision: StartupAutoRepairDecision,
        completion: @escaping (Bool) -> Void
    ) {
        switch decision {
        case .noRepairNeeded:
            reportHelperServiceEvent("Auto-aktualizacja helpera: brak potrzeby naprawy (wersja/build bez zmian).")
            completion(true)

        case .needsRepair(let previousFingerprint):
            let currentFingerprint = currentAppRepairFingerprint()
            let previousDescription = previousFingerprint ?? "brak"
            reportHelperServiceEvent(
                "Auto-aktualizacja helpera: wykryto zmianę wersji/builda aplikacji lub brak poprzedniego fingerprintu (stary=\(previousDescription), nowy=\(currentFingerprint))."
            )

            performFullRepairFromMenu { ready, message in
                if ready {
                    self.storeSuccessfulHelperRepairFingerprint(currentFingerprint)
                    self.reportHelperServiceEvent(
                        "Auto-aktualizacja helpera zakończona sukcesem dla fingerprintu \(currentFingerprint)."
                    )
                    completion(true)
                    return
                }

                let details = message ?? String(localized: "Nieznany błąd")
                self.reportHelperServiceEvent(
                    "Auto-aktualizacja helpera zakończona błędem: \(details)."
                )
                DispatchQueue.main.async {
                    self.presentAutomaticHelperUpdateFailureAlert()
                }
                completion(false)
            }
        }
    }

    private func startupAutoRepairDecision() -> StartupAutoRepairDecision {
        let currentFingerprint = currentAppRepairFingerprint()
        let defaults = UserDefaults.standard
        let previousFingerprint = defaults.string(forKey: Self.helperRepairFingerprintDefaultsKey)

        guard let previousFingerprint else {
            return .needsRepair(previousFingerprint: nil)
        }

        if previousFingerprint != currentFingerprint {
            return .needsRepair(previousFingerprint: previousFingerprint)
        }

        return .noRepairNeeded
    }

    private func currentAppRepairFingerprint() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version)-\(build)"
    }

    private func storeSuccessfulHelperRepairFingerprint(_ fingerprint: String) {
        UserDefaults.standard.set(fingerprint, forKey: Self.helperRepairFingerprintDefaultsKey)
    }

    func requiresBackgroundApproval() -> Bool {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        return service.status == .requiresApproval
    }

    func refreshBackgroundApprovalState(completion: ((Bool) -> Void)? = nil) {
        let requiresApproval = requiresBackgroundApproval()
        DispatchQueue.main.async {
            MenuState.shared.helperRequiresBackgroundApproval = requiresApproval
            completion?(requiresApproval)
        }
    }
    func presentStartupApprovalAlertIfNeeded(completion: @escaping () -> Void) {
        coordinationQueue.async {
            guard !self.didPresentStartupApprovalPrompt else {
                DispatchQueue.main.async {
                    completion()
                }
                return
            }

            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            guard service.status == .requiresApproval else {
                DispatchQueue.main.async {
                    completion()
                }
                return
            }

            self.didPresentStartupApprovalPrompt = true
            DispatchQueue.main.async {
                self.presentApprovalRequiredAlert(onDismiss: completion)
            }
        }
    }

}
