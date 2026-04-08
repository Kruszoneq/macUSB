import SwiftUI
import AppKit

@MainActor
final class MacOSDownloaderWindowManager {
    static let shared = MacOSDownloaderWindowManager()
    private let downloaderWindowHeight: CGFloat = 650

    private var sheetWindow: NSWindow?

    private init() {}

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
        NSApp.activate(ignoringOtherApps: true)

        AppLogging.info(
            "Zamknieto okno menedzera pobierania systemow macOS.",
            category: "Downloader"
        )
    }
}
