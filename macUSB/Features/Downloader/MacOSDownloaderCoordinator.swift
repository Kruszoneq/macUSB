import SwiftUI
import AppKit

enum DownloaderSourceKind: Hashable {
    case macOS
    case linux
}

@MainActor
final class MacOSDownloaderWindowManager {
    static let shared = MacOSDownloaderWindowManager()
    private let downloaderWindowHeight: CGFloat = 650

    private var sheetWindow: NSWindow?
    private var operationToken: AppActiveOperationToken?
    private var hasPresentedUnrecognizedLocalInstallerAlert = false

    private init() {}

    func claimUnrecognizedLocalInstallerAlertPresentation() -> Bool {
        guard !hasPresentedUnrecognizedLocalInstallerAlert else {
            return false
        }
        hasPresentedUnrecognizedLocalInstallerAlert = true
        return true
    }

    func present(source: DownloaderSourceKind = .macOS) {
        guard !MenuState.shared.isDownloaderAccessBlocked else {
            AppLogging.info(
                "Downloader opening blocked: USB creation is running or showing its summary.",
                stage: .downloader
            )
            return
        }

        if let sheetWindow {
            sheetWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
            AppLogging.error(
                "Cannot open downloader: no active macUSB window.",
                stage: .downloader
            )
            return
        }

        let sheetContentHeight = downloaderWindowHeight
        MenuState.shared.lockLanguageChanges(reason: "downloader_opened")

        let contentView = MacOSDownloaderWindowShellView(
            contentHeight: sheetContentHeight,
            initialSource: source
        ) { [weak self] in
            self?.close()
        }
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        let fixedSize = NSSize(
            width: MacUSBDesignTokens.windowWidth,
            height: sheetContentHeight
        )

        window.styleMask = [.titled]
        window.title = String(localized: "Pobieranie systemu macOS")
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.isReleasedWhenClosed = false
        window.center()

        sheetWindow = window
        operationToken = AppActiveOperationRegistry.shared.begin(
            kind: .downloader,
            context: "macos_downloader_window"
        )
        parentWindow.beginSheet(window)

        AppLogging.info(
            "Opened the downloader window (tab: \(source)).",
            stage: .downloader
        )
    }

    func close() {
        guard let window = sheetWindow else { return }

        if let parent = window.sheetParent {
            parent.endSheet(window)
            parent.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
        }

        sheetWindow = nil
        operationToken?.finish()
        operationToken = nil
        NSApp.activate(ignoringOtherApps: true)

        AppLogging.info(
            "Closed the macOS downloader window.",
            stage: .downloader
        )
    }
}
