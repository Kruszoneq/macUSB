import Foundation
import AppKit
import UserNotifications

final class NotificationPermissionManager {
    static let shared = NotificationPermissionManager()

    private let startupPromptHandledKey = "NotificationsStartupPromptHandledV1"
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
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus

            if self.isSystemAuthorized(status) {
                self.ensureInAppToggleDefault()
                UserDefaults.standard.set(true, forKey: self.startupPromptHandledKey)
                UserDefaults.standard.synchronize()
                self.refreshState()
                return
            }

            if status == .denied {
                UserDefaults.standard.set(true, forKey: self.startupPromptHandledKey)
                UserDefaults.standard.synchronize()
                self.refreshState()
                return
            }

            let startupHandled = UserDefaults.standard.bool(forKey: self.startupPromptHandledKey)
            guard !startupHandled else {
                self.refreshState()
                return
            }

            DispatchQueue.main.async {
                self.presentEnableNotificationsPrompt(markStartupHandled: true)
            }
        }
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
                    self.presentEnableNotificationsPrompt(markStartupHandled: false)
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

    private func presentEnableNotificationsPrompt(markStartupHandled: Bool) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Czy chcesz włączyć powiadomienia?")
        alert.informativeText = String(localized: "Pozwoli to na otrzymanie informacji o zakończeniu procesu przygotowania nośnika instalacyjnego.")
        alert.addButton(withTitle: String(localized: "Włącz powiadomienia"))
        alert.addButton(withTitle: String(localized: "Nie teraz"))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if markStartupHandled {
                UserDefaults.standard.set(true, forKey: self.startupPromptHandledKey)
                UserDefaults.standard.synchronize()
            }

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
        alert.messageText = String(localized: "Powiadomienia są wyłączone")
        alert.informativeText = String(localized: "Powiadomienia dla macUSB zostały zablokowane w ustawieniach systemowych. Aby otrzymywać informacje o zakończeniu procesów, należy zezwolić aplikacji na ich wyświetlanie w systemie.")
        alert.addButton(withTitle: String(localized: "Przejdź do ustawień systemowych"))
        alert.addButton(withTitle: String(localized: "Nie teraz"))

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
            defaults.set(true, forKey: notificationsEnabledInAppKey)
            defaults.synchronize()
        }
    }

    private func isEnabledInApp() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: notificationsEnabledInAppKey) == nil {
            return true
        }
        return defaults.bool(forKey: notificationsEnabledInAppKey)
    }

    private func setEnabledInApp(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: notificationsEnabledInAppKey)
        UserDefaults.standard.synchronize()
    }
}
