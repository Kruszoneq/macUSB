import Foundation

extension UniversalInstallationView {
    func runWindowsMacUSBootPreflight(completion: @escaping (Bool, String?) -> Void) {
        guard windowsMacUSBootPreflightRequired else {
            completion(true, nil)
            return
        }
        guard !windowsMacUSBootPreflightInProgress else { return }

        windowsMacUSBootPreflightInProgress = true
        log("macUSBoot preflight: sprawdzam gotowość i capability helpera.", category: "WindowsInstallFlow")

        HelperServiceManager.shared.ensureReadyForPrivilegedWork { ready, message in
            guard ready else {
                windowsMacUSBootPreflightInProgress = false
                completion(false, message)
                return
            }

            queryWindowsMacUSBootCapability(allowReload: true) { supported, capabilityMessage in
                windowsMacUSBootPreflightInProgress = false
                completion(supported, capabilityMessage)
            }
        }
    }

    private func queryWindowsMacUSBootCapability(
        allowReload: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        PrivilegedOperationClient.shared.queryCapabilities { result in
            switch result {
            case .success(let capabilities):
                if capabilities.contains(PrivilegedOperationClient.windowsMacUSBootCapability) {
                    log(
                        "macUSBoot preflight: capability \(PrivilegedOperationClient.windowsMacUSBootCapability) dostępna.",
                        category: "WindowsInstallFlow"
                    )
                    completion(true, nil)
                    return
                }
                reloadWindowsMacUSBootHelperIfAllowed(allowReload: allowReload, completion: completion)

            case .failure(let error):
                logError("macUSBoot preflight: odczyt capability nieudany: \(error.localizedDescription)", category: "WindowsInstallFlow")
                reloadWindowsMacUSBootHelperIfAllowed(allowReload: allowReload, completion: completion)
            }
        }
    }

    private func reloadWindowsMacUSBootHelperIfAllowed(
        allowReload: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard allowReload else {
            completion(false, String(localized: "Nie udało się automatycznie odświeżyć helpera. Otwórz Narzędzia → Napraw helpera i spróbuj ponownie."))
            return
        }

        log("macUSBoot preflight: capability niedostępna, przeładowuję helpera.", category: "WindowsInstallFlow")
        HelperServiceManager.shared.forceReloadForIPCContractMismatch { ready, message in
            guard ready else {
                completion(false, message)
                return
            }
            queryWindowsMacUSBootCapability(allowReload: false, completion: completion)
        }
    }
}
