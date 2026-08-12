import SwiftUI
import AppKit

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

    func present() {
        guard !MenuState.shared.isDownloaderAccessBlocked else {
            AppLogging.info(
                "Otwarcie downloadera zablokowane: trwa lub podsumowuje sie proces tworzenia nośnika USB.",
                category: "Downloader"
            )
            return
        }

        if let sheetWindow {
            sheetWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
            AppLogging.error(
                "Nie mozna otworzyc okna downloadera: brak aktywnego okna macUSB.",
                category: "Downloader"
            )
            return
        }

        let sheetContentHeight = downloaderWindowHeight
        MenuState.shared.lockLanguageChanges(reason: "downloader_opened")

        let contentView = MacOSDownloaderWindowShellView(contentHeight: sheetContentHeight) { [weak self] in
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
            "Otwarto okno menedzera pobierania systemow macOS.",
            category: "Downloader"
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
            "Zamknieto okno menedzera pobierania systemow macOS.",
            category: "Downloader"
        )
    }
}
