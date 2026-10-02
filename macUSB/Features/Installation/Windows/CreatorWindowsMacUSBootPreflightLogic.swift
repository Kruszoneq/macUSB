import Foundation

extension UniversalInstallationView {
    func runWindowsMacUSBootPreflight(completion: @escaping (Bool, String?) -> Void) {
        guard windowsMacUSBootPreflightRequired else {
            completion(true, nil)
            return
        }
        guard !windowsMacUSBootPreflightInProgress else { return }

        windowsMacUSBootPreflightInProgress = true
        log("macUSBoot preflight: checking helper readiness and capability.", category: "WindowsInstallFlow")

        HelperServiceManager.shared.ensureReadyForPrivilegedWork { ready, message in
            guard ready else {
                logError("macUSBoot preflight: helper is not ready: \(message ?? "no details")", category: "WindowsInstallFlow")
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
                        "macUSBoot preflight: capability \(PrivilegedOperationClient.windowsMacUSBootCapability) is available.",
                        category: "WindowsInstallFlow"
                    )
                    completion(true, nil)
                    return
                }
                reloadWindowsMacUSBootHelperIfAllowed(allowReload: allowReload, completion: completion)

            case .failure(let error):
                logError("macUSBoot preflight: capability query failed: \(error.localizedDescription)", category: "WindowsInstallFlow")
                reloadWindowsMacUSBootHelperIfAllowed(allowReload: allowReload, completion: completion)
            }
        }
    }

    private func reloadWindowsMacUSBootHelperIfAllowed(
        allowReload: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard allowReload else {
            logError("macUSBoot preflight: capability remains unavailable after helper reload.", category: "WindowsInstallFlow")
            completion(false, String(localized: "creator.error.helper_refresh_failed", table: "Creator"))
            return
        }

        log("macUSBoot preflight: capability unavailable; reloading the helper.", category: "WindowsInstallFlow")
        HelperServiceManager.shared.forceReloadForIPCContractMismatch { ready, message in
            guard ready else {
                completion(false, message)
                return
            }
            queryWindowsMacUSBootCapability(allowReload: false, completion: completion)
        }
    }
}
