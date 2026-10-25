import AppKit
import SwiftUI

extension MacOSDownloaderWindowShellView {
    func presentDiskImageCollisionAlert(
        context: MacOSDiskImageCollisionContext
    ) -> Bool {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "downloader.disk_image.collision.title", table: "Downloader")
        alert.informativeText = String(
            format: String(localized: "downloader.disk_image.collision.message", table: "Downloader"),
            context.directoryURL.path,
            context.existingFileName,
            context.proposedFileName
        )
        alert.addButton(
            withTitle: String(localized: "downloader.disk_image.collision.continue", table: "Downloader")
        )
        alert.addButton(
            withTitle: String(localized: "downloader.disk_image.collision.cancel", table: "Downloader")
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentInsufficientDiskSpaceAlert(context: DiskSpaceAlertContext) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning

        switch context.diskImageLocation {
        case .systemVolume:
            alert.messageText = String(localized: "downloader.disk_image.space.system.title", table: "Downloader")
            alert.informativeText = String(
                format: String(localized: "downloader.disk_image.space.system.message", table: "Downloader"),
                context.requiredMinimumText,
                context.availableText
            )
            alert.addButton(
                withTitle: String(localized: "downloader.disk_image.space.return", table: "Downloader")
            )
        case .destinationVolume:
            alert.messageText = String(localized: "downloader.disk_image.space.destination.title", table: "Downloader")
            alert.informativeText = String(
                format: String(localized: "downloader.disk_image.space.destination.message", table: "Downloader"),
                context.requiredMinimumText,
                context.availableText
            )
            alert.addButton(
                withTitle: String(localized: "downloader.disk_image.space.return", table: "Downloader")
            )
        case nil:
            alert.messageText = String(localized: "downloader.space.alert.title", table: "Downloader")
            alert.informativeText = String(
                format: String(localized: "downloader.space.alert.message", table: "Downloader"),
                context.requiredMinimumText,
                context.availableText
            )
            alert.addButton(withTitle: String(localized: "downloader.action.ok", table: "Downloader"))
        }

        alert.runModal()
        if context.diskImageLocation == nil {
            handleCloseRequest()
        }
    }

    func presentDiskImageFolderUnavailableAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "downloader.disk_image.folder_unavailable.title", table: "Downloader"
        )
        alert.informativeText = String(
            localized: "downloader.disk_image.folder_unavailable.message", table: "Downloader"
        )
        alert.addButton(
            withTitle: String(localized: "downloader.disk_image.space.return", table: "Downloader")
        )
        alert.runModal()
    }

    func returnToInstallerListAfterDiskImagePreflight() {
        downloadFlowModel.stop()
        downloadFlowModel.resetState()
        withAnimation(MacUSBDesignTokens.stageTransitionAnimation) {
            activeDownloadEntry = nil
        }
    }
}
