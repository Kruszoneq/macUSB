import AppKit

/// Keeps the persisted option disabled until the user confirms its behavior.
final class WelcomeAutoSkipPreferences {
    static let shared = WelcomeAutoSkipPreferences()

    private var isPresentingConfirmation = false

    private init() {}

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            MenuState.shared.skipWelcomeEnabled = false
            return
        }
        guard !MenuState.shared.skipWelcomeEnabled, !isPresentingConfirmation else { return }
        isPresentingConfirmation = true
        let wasWelcomeActiveWhenRequested = WelcomeStartupCoordinator.shared.isWelcomeActive

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "app.welcome.auto_skip.confirm.title", table: "App")
        alert.informativeText = String(localized: "app.welcome.auto_skip.confirm.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.welcome.auto_skip.confirm.action", table: "App"))
        alert.addButton(withTitle: String(localized: "app.action.cancel", table: "App"))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            // Wait for the sheet/modal to finish closing before publishing the option.
            DispatchQueue.main.async {
                self.isPresentingConfirmation = false
                guard response == .alertFirstButtonReturn else { return }
                let startupCoordinator = WelcomeStartupCoordinator.shared
                let canApplyToCurrentWelcome = wasWelcomeActiveWhenRequested && startupCoordinator.isWelcomeActive
                if !canApplyToCurrentWelcome {
                    // Enabling from another screen applies only to a future launch.
                    startupCoordinator.cancelAutomaticNavigation()
                }
                MenuState.shared.skipWelcomeEnabled = true
                if canApplyToCurrentWelcome {
                    startupCoordinator.refreshPrerequisitesIfNeeded()
                }
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }
}
