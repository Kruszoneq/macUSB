import AppKit
import Foundation

@MainActor
final class AppTerminationCoordinator {
    static let shared = AppTerminationCoordinator()

    private var blockedAlert: NSAlert?

    private init() {}

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        let operations = AppActiveOperationRegistry.shared.snapshot()
        guard operations.isEmpty else {
            reportBlockedTermination(operations: operations, source: "application_termination")
            presentBlockedAlert()
            return .terminateCancel
        }

        AppTerminationCleanup.shared.performIfNeeded()
        return .terminateNow
    }

    func shouldAllowWindowClose() -> Bool {
        let operations = AppActiveOperationRegistry.shared.snapshot()
        guard operations.isEmpty else {
            reportBlockedTermination(operations: operations, source: "main_window_close")
            presentBlockedAlert()
            return false
        }
        return true
    }

    private func reportBlockedTermination(
        operations: [AppActiveOperationSnapshot],
        source: String
    ) {
        let now = Date()
        let details = operations.map { operation in
            let duration = max(0, now.timeIntervalSince(operation.startedAt))
            return String(
                format: "%@:%@ (%.2fs, %@)",
                operation.kind.rawValue,
                operation.context,
                duration,
                operation.id.uuidString
            )
        }.joined(separator: ", ")

        AppLogging.info(
            "Zablokowano zamknięcie aplikacji [source=\(source), active=\(details)].",
            category: "AppLifecycle"
        )
    }

    private func presentBlockedAlert() {
        if let blockedAlert {
            NSApp.activate(ignoringOtherApps: true)
            blockedAlert.window.makeKeyAndOrderFront(nil)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "app.termination.active.title")
        alert.informativeText = String(localized: "app.termination.active.message")
        alert.addButton(withTitle: String(localized: "app.termination.active.confirm"))
        blockedAlert = alert

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] _ in
            self?.blockedAlert = nil
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window != alert.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            _ = alert.runModal()
            blockedAlert = nil
        }
    }
}
