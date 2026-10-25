import Foundation
import AppKit
import UserNotifications

final class NotificationPermissionManager {
    static let shared = NotificationPermissionManager()

    private let notificationsEnabledInAppKey = "NotificationsEnabledInAppV1"

    private init() {}

    func refreshState() {
        let enabledInApp = isEnabledInApp()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let enabledInSystem = self.isSystemAuthorized(settings.authorizationStatus)
            DispatchQueue.main.async {
                MenuState.shared.notificationsEnabled = enabledInSystem && enabledInApp
            }
        }
    }

    func handleStartupFlowIfNeeded() {
        // No startup notification prompt. First launch defaults to disabled,
        // and permission request is user-initiated from menu action.
        ensureInAppToggleDefault()
        refreshState()
    }

    func handleMenuNotificationsTapped() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus

            if self.isSystemAuthorized(status) {
                let currentlyEnabled = self.isEnabledInApp()
                self.setEnabledInApp(!currentlyEnabled)
                self.refreshState()
                return
            }

            if status == .notDetermined {
                DispatchQueue.main.async {
                    self.presentEnableNotificationsPrompt()
                }
                return
            }

            DispatchQueue.main.async {
                self.presentSystemBlockedAlert()
            }
        }
    }

    func shouldDeliverInAppNotification(completion: @escaping (Bool) -> Void) {
        let enabledInApp = isEnabledInApp()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let canDeliver = enabledInApp && self.isSystemAuthorized(settings.authorizationStatus)
            DispatchQueue.main.async {
                completion(canDeliver)
            }
        }
    }

    private func presentEnableNotificationsPrompt() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "app.notifications.enable.title", table: "App")
        alert.informativeText = String(localized: "app.notifications.enable.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.notifications.enable.action", table: "App"))
        alert.addButton(withTitle: String(localized: "app.action.not_now", table: "App"))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                self.setEnabledInApp(true)
                self.requestSystemAuthorization()
            } else {
                self.refreshState()
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func presentSystemBlockedAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "app.notifications.disabled.title", table: "App")
        alert.informativeText = String(localized: "app.notifications.disabled.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.open_system_settings", table: "App"))
        alert.addButton(withTitle: String(localized: "app.action.not_now", table: "App"))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                self.openSystemNotificationSettings()
            }
            self.refreshState()
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func requestSystemAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            self.refreshState()
        }
    }

    private func openSystemNotificationSettings() {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let encodedBundleId = bundleId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleId

        let candidates = [
            "x-apple.systempreferences:com.apple.preference.notifications?id=\(encodedBundleId)",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }

        let settingsBundleIDs = ["com.apple.systempreferences", "com.apple.SystemSettings"]
        for settingsBundleID in settingsBundleIDs {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: settingsBundleID) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                return
            }
        }
    }

    private func isSystemAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        return status == .authorized || status == .provisional
    }

    private func ensureInAppToggleDefault() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: notificationsEnabledInAppKey) == nil {
            defaults.set(false, forKey: notificationsEnabledInAppKey)
            defaults.synchronize()
        }
    }

    private func isEnabledInApp() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: notificationsEnabledInAppKey) == nil {
            return false
        }
        return defaults.bool(forKey: notificationsEnabledInAppKey)
    }

    private func setEnabledInApp(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: notificationsEnabledInAppKey)
        UserDefaults.standard.synchronize()
    }
}
