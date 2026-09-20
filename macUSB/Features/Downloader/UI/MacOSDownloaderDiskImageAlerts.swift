import AppKit
import SwiftUI

extension MacOSDownloaderWindowShellView {
    func presentDiskImageCollisionAlert(
        context: MacOSDiskImageCollisionContext
    ) -> Bool {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "downloader.disk_image.collision.title")
        alert.informativeText = String(
            format: String(localized: "downloader.disk_image.collision.message"),
            context.directoryURL.path,
            context.existingFileName,
            context.proposedFileName
        )
        alert.addButton(
            withTitle: String(localized: "downloader.disk_image.collision.continue")
        )
        alert.addButton(
            withTitle: String(localized: "downloader.disk_image.collision.cancel")
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentInsufficientDiskSpaceAlert(context: DiskSpaceAlertContext) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning

        switch context.diskImageLocation {
        case .systemVolume:
            alert.messageText = String(localized: "downloader.disk_image.space.system.title")
            alert.informativeText = String(
                format: String(localized: "downloader.disk_image.space.system.message"),
                context.requiredMinimumText,
                context.availableText
            )
            alert.addButton(
                withTitle: String(localized: "downloader.disk_image.space.return")
            )
        case .destinationVolume:
            alert.messageText = String(localized: "downloader.disk_image.space.destination.title")
            alert.informativeText = String(
                format: String(localized: "downloader.disk_image.space.destination.message"),
                context.requiredMinimumText,
                context.availableText
            )
            alert.addButton(
                withTitle: String(localized: "downloader.disk_image.space.return")
            )
        case nil:
            alert.messageText = String(localized: "Za mało miejsca na dysku")
            alert.informativeText = String(
                format: String(localized: "Aby rozpocząć pobieranie, potrzebujesz więcej wolnego miejsca na dysku.\n\nWymagane minimum: %@. Dostępne: %@.\n\nZwolnij miejsce i spróbuj ponownie."),
                context.requiredMinimumText,
                context.availableText
            )
            alert.addButton(withTitle: String(localized: "OK"))
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
            localized: "downloader.disk_image.folder_unavailable.title"
        )
        alert.informativeText = String(
            localized: "downloader.disk_image.folder_unavailable.message"
        )
        alert.addButton(
            withTitle: String(localized: "downloader.disk_image.space.return")
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
