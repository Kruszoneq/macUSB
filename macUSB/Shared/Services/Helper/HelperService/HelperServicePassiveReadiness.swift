import Foundation
import ServiceManagement

enum HelperPassiveReadinessState: String {
    case ready
    case requiresBackgroundApproval
    case unavailable
}

struct HelperPassiveReadinessSnapshot {
    let state: HelperPassiveReadinessState
    let serviceStatus: SMAppService.Status
    let healthDetails: String?
}

extension HelperServiceManager {
    func evaluatePassiveReadiness(
        completion: @escaping (HelperPassiveReadinessSnapshot) -> Void
    ) {
        let serviceStatus = SMAppService.daemon(plistName: Self.daemonPlistName).status
        let requiresBackgroundApproval = serviceStatus == .requiresApproval

        DispatchQueue.main.async {
            MenuState.shared.helperRequiresBackgroundApproval = requiresBackgroundApproval
        }

        switch serviceStatus {
        case .requiresApproval:
            DispatchQueue.main.async {
                completion(
                    HelperPassiveReadinessSnapshot(
                        state: .requiresBackgroundApproval,
                        serviceStatus: serviceStatus,
                        healthDetails: nil
                    )
                )
            }

        case .enabled:
            PrivilegedOperationClient.shared.queryHealth(
                withTimeout: statusHealthTimeout,
                presentsTrustFailureAlert: false
            ) { healthy, details in
                completion(
                    HelperPassiveReadinessSnapshot(
                        state: healthy ? .ready : .unavailable,
                        serviceStatus: serviceStatus,
                        healthDetails: healthy ? nil : details
                    )
                )
            }

        case .notRegistered, .notFound:
            DispatchQueue.main.async {
                completion(
                    HelperPassiveReadinessSnapshot(
                        state: .unavailable,
                        serviceStatus: serviceStatus,
                        healthDetails: nil
                    )
                )
            }

        @unknown default:
            DispatchQueue.main.async {
                completion(
                    HelperPassiveReadinessSnapshot(
                        state: .unavailable,
                        serviceStatus: serviceStatus,
                        healthDetails: nil
                    )
                )
            }
        }
    }
}
