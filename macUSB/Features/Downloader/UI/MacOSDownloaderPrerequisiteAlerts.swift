import AppKit
import ServiceManagement

extension MacOSDownloaderWindowShellView {
    func handlePrerequisiteWarningTap() {
        guard !prerequisiteController.isChecking else { return }

        prerequisiteController.refresh(trigger: .warningAction) { snapshot in
            guard snapshot.requiresWarning else {
                AppLogging.info(
                    "Downloader prerequisite warning is no longer current.",
                    stage: .downloader
                )
                return
            }
            presentDownloaderPrerequisiteAlert(for: snapshot)
        }
    }

    func presentDownloaderPrerequisiteAlert(
        for snapshot: MacOSDownloaderPrerequisiteSnapshot
    ) {
        let missingFullDiskAccess = !snapshot.hasFullDiskAccess

        switch (missingFullDiskAccess, snapshot.helperReadiness) {
        case (true, .requiresBackgroundApproval):
            presentCombinedPermissionsAlert()
        case (true, .unavailable):
            presentFullDiskAccessAndUnavailableHelperAlert()
        case (true, .ready):
            presentFullDiskAccessAlert()
        case (false, .requiresBackgroundApproval):
            presentBackgroundActivityAlert()
        case (false, .unavailable):
            presentUnavailableHelperAlert()
        case (false, .ready):
            break
        }
    }

    private func presentFullDiskAccessAlert() {
        let alert = makePrerequisiteAlert(
            titleKey: "downloader.prerequisites.full_disk_access.title",
            messageKey: "downloader.prerequisites.full_disk_access.message"
        )
        alert.addButton(
            withTitle: String(localized: "downloader.prerequisites.full_disk_access.open", table: "Downloader")
        )
        alert.addButton(withTitle: String(localized: "downloader.action.not_now", table: "Downloader"))
        presentPrerequisiteAlert(alert) { response in
            guard response == .alertFirstButtonReturn else { return }
            _ = FullDiskAccessPermissionManager.shared.openFullDiskAccessSettings(
                showFallbackAlertIfNeeded: false
            )
        }
    }

    private func presentBackgroundActivityAlert() {
        let alert = makePrerequisiteAlert(
            titleKey: "downloader.prerequisites.background_activity.title",
            messageKey: "downloader.prerequisites.background_activity.message"
        )
        alert.addButton(
            withTitle: String(localized: "downloader.prerequisites.background_activity.open", table: "Downloader")
        )
        alert.addButton(withTitle: String(localized: "downloader.action.not_now", table: "Downloader"))
        presentPrerequisiteAlert(alert) { response in
            guard response == .alertFirstButtonReturn else { return }
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func presentCombinedPermissionsAlert() {
        let alert = makePrerequisiteAlert(
            titleKey: "downloader.prerequisites.combined.title",
            messageKey: "downloader.prerequisites.combined.message"
        )
        alert.addButton(
            withTitle: String(localized: "downloader.prerequisites.combined.full_disk_access_action", table: "Downloader")
        )
        alert.addButton(
            withTitle: String(localized: "downloader.prerequisites.combined.background_activity_action", table: "Downloader")
        )
        alert.addButton(withTitle: String(localized: "downloader.action.not_now", table: "Downloader"))
        presentPrerequisiteAlert(alert) { response in
            switch response {
            case .alertFirstButtonReturn:
                _ = FullDiskAccessPermissionManager.shared.openFullDiskAccessSettings(
                    showFallbackAlertIfNeeded: false
                )
            case .alertSecondButtonReturn:
                SMAppService.openSystemSettingsLoginItems()
            default:
                break
            }
        }
    }

    private func presentFullDiskAccessAndUnavailableHelperAlert() {
        let alert = makePrerequisiteAlert(
            titleKey: "downloader.prerequisites.combined.title",
            messageKey: "downloader.prerequisites.full_disk_and_helper_unavailable.message"
        )
        alert.addButton(
            withTitle: String(localized: "downloader.prerequisites.combined.full_disk_access_action", table: "Downloader")
        )
        alert.addButton(withTitle: String(localized: "downloader.action.close", table: "Downloader"))
        presentPrerequisiteAlert(alert) { response in
            guard response == .alertFirstButtonReturn else { return }
            _ = FullDiskAccessPermissionManager.shared.openFullDiskAccessSettings(
                showFallbackAlertIfNeeded: false
            )
        }
    }

    private func presentUnavailableHelperAlert() {
        let alert = makePrerequisiteAlert(
            titleKey: "downloader.prerequisites.helper_unavailable.title",
            messageKey: "downloader.prerequisites.helper_unavailable.message"
        )
        alert.addButton(withTitle: String(localized: "downloader.action.close", table: "Downloader"))
        presentPrerequisiteAlert(alert, completion: nil)
    }

    private func makePrerequisiteAlert(titleKey: String, messageKey: String) -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: String.LocalizationValue(titleKey), table: "Downloader")
        alert.informativeText = String(localized: String.LocalizationValue(messageKey), table: "Downloader")
        return alert
    }

    private func presentPrerequisiteAlert(
        _ alert: NSAlert,
        completion: ((NSApplication.ModalResponse) -> Void)?
    ) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { response in
                completion?(response)
            }
        } else {
            let response = alert.runModal()
            completion?(response)
        }
    }
}
