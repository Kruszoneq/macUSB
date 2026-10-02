import SwiftUI
import AppKit

extension MacOSDownloaderWindowShellView {
    func presentLinuxRedownloadConfirmationAlert() -> Bool {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "downloader.linux.redownload.title")
        alert.informativeText = String(localized: "downloader.linux.redownload.message")
        alert.addButton(withTitle: String(localized: "downloader.local_installers.redownload_cancel"))
        alert.addButton(withTitle: String(localized: "downloader.local_installers.redownload_confirm"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    func presentLinuxInsufficientDiskSpaceAlert(context: DiskSpaceAlertContext) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Za mało miejsca na dysku")
        alert.informativeText = String(
            format: String(localized: "Aby rozpocząć pobieranie, potrzebujesz więcej wolnego miejsca na dysku.\n\nWymagane minimum: %@. Dostępne: %@.\n\nZwolnij miejsce i spróbuj ponownie."),
            context.requiredMinimumText,
            context.availableText
        )
        alert.addButton(withTitle: String(localized: "downloader.disk_image.space.return"))
        alert.runModal()
    }

    func returnToLinuxImageList() {
        linuxDownloadFlowModel.stop()
        linuxDownloadFlowModel.resetState()
        linuxLogic.refreshDownloadedState(destinationDirectoryURL: linuxDestinationDirectoryURL)
        withAnimation(MacUSBDesignTokens.stageTransitionAnimation) {
            activeLinuxEntry = nil
        }
    }

    func sendLinuxDownloadCompletionNotificationIfInactive(for entry: LinuxImageEntry) {
        guard !NSApp.isActive else { return }

        let title = String(localized: "Pobieranie zakończone")
        let body = String(
            format: String(localized: "Pobieranie systemu %@ %@ zostało zakończone pomyślnie."),
            entry.distribution.displayName,
            entry.edition.isEmpty ? entry.version : "\(entry.version) \(entry.edition)"
        )

        NotificationPermissionManager.shared.shouldDeliverInAppNotification { shouldDeliver in
            guard shouldDeliver else { return }
            scheduleSystemNotification(title: title, body: body)
        }
    }
}
