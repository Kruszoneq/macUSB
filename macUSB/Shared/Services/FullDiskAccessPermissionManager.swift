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

    func refreshState(completion: ((Bool) -> Void)? = nil) {
        hasFullDiskAccess { hasAccess in
            DispatchQueue.main.async {
                MenuState.shared.hasFullDiskAccess = hasAccess
                completion?(hasAccess)
            }
        }
    }

    func hasFullDiskAccess(completion: @escaping (Bool) -> Void) {
        probeQueue.async {
            let hasAccess = self.evaluateFullDiskAccess()
            completion(hasAccess)
        }
    }

    func handleStartupPromptIfNeeded(completion: @escaping () -> Void) {
        hasFullDiskAccess { hasAccess in
            DispatchQueue.main.async {
                MenuState.shared.hasFullDiskAccess = hasAccess
                guard !hasAccess else {
                    completion()
                    return
                }
                self.presentStartupPrompt(completion: completion)
            }
        }
    }

    @discardableResult
    func openFullDiskAccessSettings(showFallbackAlertIfNeeded: Bool) -> Bool {
        let deepLinkCandidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for candidate in deepLinkCandidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return true
            }
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
        refreshState()

        guard awaitingAppReactivationAfterSettingsOpen else { return }
        finishPendingStartupContinuationIfNeeded()
    }

    private func evaluateFullDiskAccess() -> Bool {
        let tccDatabaseURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db", isDirectory: false)

        guard FileManager.default.fileExists(atPath: tccDatabaseURL.path) else {
            return false
        }

        do {
            let handle = try FileHandle(forReadingFrom: tccDatabaseURL)
            defer {
                try? handle.close()
            }

            if #available(macOS 10.15.4, *) {
                _ = try handle.read(upToCount: 1)
            } else {
                _ = handle.readData(ofLength: 1)
            }
            return true
        } catch {
            return false
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
