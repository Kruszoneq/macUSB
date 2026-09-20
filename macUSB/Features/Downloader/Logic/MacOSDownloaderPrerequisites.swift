import Foundation
import Combine
import ServiceManagement

enum MacOSDownloaderPrerequisiteCheckTrigger: String {
    case initialPresentation
    case appActivation
    case warningAction
    case downloadAction
}

struct MacOSDownloaderPrerequisiteSnapshot {
    let fullDiskAccessStatus: FullDiskAccessStatus
    let helperReadiness: HelperPassiveReadinessState
    let helperServiceStatus: SMAppService.Status
    let helperHealthDetails: String?

    var hasFullDiskAccess: Bool {
        fullDiskAccessStatus.hasConfirmedAccess
    }

    var isHelperReady: Bool {
        helperReadiness == .ready
    }

    var allowsDownload: Bool {
        hasFullDiskAccess && isHelperReady
    }

    var requiresWarning: Bool {
        !allowsDownload
    }
}

final class MacOSDownloaderPrerequisiteController: ObservableObject {
    @Published private(set) var snapshot: MacOSDownloaderPrerequisiteSnapshot?
    @Published private(set) var isChecking = false

    private var activeCheckID: UUID?

    func refresh(
        trigger: MacOSDownloaderPrerequisiteCheckTrigger,
        completion: ((MacOSDownloaderPrerequisiteSnapshot) -> Void)? = nil
    ) {
        guard !isChecking else {
            AppLogging.info(
                "Pominieto rownolegle sprawdzenie wymagan downloadera " +
                "[trigger=\(trigger.rawValue)].",
                category: "Downloader"
            )
            return
        }

        let checkID = UUID()
        activeCheckID = checkID
        isChecking = true

        AppLogging.info(
            "Rozpoczynam pasywne sprawdzenie wymagan downloadera [trigger=\(trigger.rawValue)].",
            category: "Downloader"
        )

        var fullDiskAccessStatus: FullDiskAccessStatus?
        var helperSnapshot: HelperPassiveReadinessSnapshot?

        let finishIfComplete = { [weak self] in
            guard let self,
                  self.activeCheckID == checkID,
                  let fullDiskAccessStatus,
                  let helperSnapshot
            else { return }

            let result = MacOSDownloaderPrerequisiteSnapshot(
                fullDiskAccessStatus: fullDiskAccessStatus,
                helperReadiness: helperSnapshot.state,
                helperServiceStatus: helperSnapshot.serviceStatus,
                helperHealthDetails: helperSnapshot.healthDetails
            )

            self.snapshot = result
            self.isChecking = false
            self.activeCheckID = nil

            let statusMessage =
                "Zakonczono pasywne sprawdzenie wymagan downloadera " +
                "[trigger=\(trigger.rawValue), fda=\(fullDiskAccessStatus.rawValue), " +
                "helper=\(helperSnapshot.state.rawValue), " +
                "service=\(self.serviceStatusDiagnosticName(helperSnapshot.serviceStatus)), " +
                "allowsDownload=\(result.allowsDownload)]."
            AppLogging.info(statusMessage, category: "Downloader")

            if let details = helperSnapshot.healthDetails, !details.isEmpty {
                AppLogging.error(
                    "Pasywny health-check XPC downloadera nie powiodl sie: \(details)",
                    category: "Downloader"
                )
            }

            completion?(result)
        }

        FullDiskAccessPermissionManager.shared.refreshState(trigger: .downloader) { status in
            guard self.activeCheckID == checkID else { return }
            fullDiskAccessStatus = status
            finishIfComplete()
        }

        HelperServiceManager.shared.evaluatePassiveReadiness { result in
            guard self.activeCheckID == checkID else { return }
            helperSnapshot = result
            finishIfComplete()
        }
    }

    func invalidate() {
        activeCheckID = nil
        isChecking = false
    }

    private func serviceStatusDiagnosticName(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requiresApproval"
        case .notRegistered:
            return "notRegistered"
        case .notFound:
            return "notFound"
        @unknown default:
            return "unknown"
        }
    }
}
