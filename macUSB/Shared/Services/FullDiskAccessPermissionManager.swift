import Foundation
import AppKit

final class FullDiskAccessPermissionManager {
    static let shared = FullDiskAccessPermissionManager()

    private let probeQueue = DispatchQueue(label: "macUSB.permissions.fullDiskAccess", qos: .userInitiated)
    private var awaitingAppReactivationAfterSettingsOpen = false
    private var pendingStartupCompletion: (() -> Void)?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refreshState(
        trigger: FullDiskAccessCheckTrigger,
        completion: ((FullDiskAccessStatus) -> Void)? = nil
    ) {
        probeQueue.async {
            let evaluation = self.evaluateFullDiskAccess(trigger: trigger)
            DispatchQueue.main.async {
                self.publish(evaluation.status)
                completion?(evaluation.status)
            }
        }
    }

    func handleStartupPromptIfNeeded(completion: @escaping () -> Void) {
        probeQueue.async {
            let evaluation = self.evaluateFullDiskAccess(trigger: .startup)
            DispatchQueue.main.async {
                self.publish(evaluation.status)
                guard !evaluation.status.hasConfirmedAccess else {
                    completion()
                    return
                }
                self.presentStartupPrompt(completion: completion)
            }
        }
    }

    @discardableResult
    func openFullDiskAccessSettings(showFallbackAlertIfNeeded: Bool) -> Bool {
        let evaluation = evaluateFullDiskAccess(trigger: .settingsPanel)
        publish(evaluation.status)

        let fullDiskAccessSettingsURL =
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        if let url = URL(string: fullDiskAccessSettingsURL), NSWorkspace.shared.open(url) {
            return true
        }

        let settingsBundleIDs = ["com.apple.systempreferences", "com.apple.SystemSettings"]
        for settingsBundleID in settingsBundleIDs {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: settingsBundleID) else {
                continue
            }
            if showFallbackAlertIfNeeded {
                presentSettingsFallbackAlert()
            }
            return NSWorkspace.shared.open(appURL)
        }

        if showFallbackAlertIfNeeded {
            presentSettingsFallbackAlert()
        }
        return false
    }

    @objc
    private func handleAppDidBecomeActive() {
        guard awaitingAppReactivationAfterSettingsOpen else { return }
        finishPendingStartupContinuationIfNeeded()
    }

    private func evaluateFullDiskAccess(
        trigger: FullDiskAccessCheckTrigger
    ) -> FullDiskAccessEvaluation {
        AppLogging.info(
            "FDA check started: trigger=\(trigger.rawValue).",
            category: "Permissions"
        )

        let evaluation = FullDiskAccessProbe.evaluate()
        for result in evaluation.results {
            var message =
                "FDA probe: trigger=\(trigger.rawValue), id=\(result.identifier.rawValue), " +
                "operation=\(result.operation.rawValue), path=\(result.path)"
            if let errnoCode = result.errnoCode {
                let description = result.errorDescription ?? "Unknown error"
                message += ", errno=\(errnoCode) (\(description))"
            } else {
                message += ", errno=none"
            }
            message += ", signal=\(result.signal.rawValue)."
            AppLogging.info(message, category: "Permissions")
        }

        AppLogging.info(
            "FDA check completed: trigger=\(trigger.rawValue), status=\(evaluation.status.rawValue).",
            category: "Permissions"
        )
        return evaluation
    }

    private func publish(_ status: FullDiskAccessStatus) {
        let update = {
            MenuState.shared.hasFullDiskAccess = status.hasConfirmedAccess
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.sync(execute: update)
        }
    }

    private func presentStartupPrompt(completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Wymagany pełny dostęp do dysku")
        alert.informativeText = String(localized: "Aby aplikacja macUSB działała poprawnie, przyznaj jej uprawnienie „Pełny dostęp do dysku” w ustawieniach systemowych.")
        alert.addButton(withTitle: String(localized: "Przejdź do ustawień systemowych"))
        alert.addButton(withTitle: String(localized: "Nie teraz"))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                let opened = self.openFullDiskAccessSettings(showFallbackAlertIfNeeded: true)
                if opened {
                    self.awaitingAppReactivationAfterSettingsOpen = true
                    self.pendingStartupCompletion = completion
                    self.scheduleFallbackContinuationIfAppStaysActive()
                } else {
                    completion()
                }
                return
            }

            completion()
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func presentSettingsFallbackAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Otworzono Ustawienia systemowe")
        alert.informativeText = String(localized: "Nie udało się otworzyć bezpośrednio zakładki „Pełny dostęp do dysku”. Przejdź do: Prywatność i ochrona -> Pełny dostęp do dysku.")
        alert.addButton(withTitle: String(localized: "OK"))

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func scheduleFallbackContinuationIfAppStaysActive() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard self.awaitingAppReactivationAfterSettingsOpen else { return }
            guard NSApp.isActive else { return }
            self.finishPendingStartupContinuationIfNeeded()
        }
    }

    private func finishPendingStartupContinuationIfNeeded() {
        awaitingAppReactivationAfterSettingsOpen = false
        let completion = pendingStartupCompletion
        pendingStartupCompletion = nil
        completion?()
    }
}
