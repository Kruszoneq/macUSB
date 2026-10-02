import Foundation
import AppKit
import ServiceManagement
import Darwin

extension HelperServiceManager {
    func diagnosticStatusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "not registered"
        case .requiresApproval: return "requires approval"
        case .notFound: return "not found"
        @unknown default: return "unknown"
        }
    }

    func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return String(localized: "app.helper.status.enabled", table: "App")
        case .notRegistered:
            return String(localized: "app.helper.status.not_registered", table: "App")
        case .requiresApproval:
            return String(localized: "app.helper.status.requires_approval", table: "App")
        case .notFound:
            return String(localized: "app.helper.status.not_found", table: "App")
        @unknown default:
            return String(localized: "app.helper.status.unknown", table: "App")
        }
    }
    func isAppInstalledInApplications() -> Bool {
        let bundlePath = Bundle.main.bundleURL.standardized.path
        return bundlePath.hasPrefix("/Applications/")
    }
    func isLocationRequirementSatisfied() -> Bool {
        if isAppInstalledInApplications() {
            return true
        }
        #if DEBUG
        return Self.isRunningFromXcodeDevelopmentBuild()
        #else
        return false
        #endif
    }

    #if DEBUG
    static func isRunningFromXcodeDevelopmentBuild() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil {
            return true
        }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        let bundlePath = Bundle.main.bundleURL.standardized.path
        return bundlePath.contains("/DerivedData/") && bundlePath.contains("/Build/Products/")
    }
    #endif
    func presentMoveToApplicationsAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "app.helper.location.required.title", table: "App")
        alert.informativeText = String(localized: "app.helper.location.required.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        presentAlert(alert)
    }
    func presentApprovalRequiredAlert(onDismiss: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "app.helper.approval.required.title", table: "App")
        alert.informativeText = String(localized: "app.helper.approval.required.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.open_system_settings", table: "App"))
        alert.addButton(withTitle: String(localized: "app.action.not_now", table: "App"))

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
            onDismiss?()
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
    func presentRegistrationErrorAlertIfNeeded(error: Error, interactive: Bool) {
        guard interactive else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "app.helper.registration.failure.title", table: "App")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        presentAlert(alert)
    }
    func presentAutomaticHelperUpdateFailureAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "app.helper.auto_update.failure.title", table: "App")
        alert.informativeText = String(localized: "app.helper.auto_update.failure.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.acknowledge", table: "App"))
        presentAlert(alert)
    }
    func presentHelperTrustVerificationFailureAlert() {
        DispatchQueue.main.async {
            guard self.helperTrustVerificationAlertWindow == nil else { return }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = HelperConnectionSecurityPolicy.localizedFailureTitle
            alert.informativeText = HelperConnectionSecurityPolicy.localizedFailureMessage
            alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))

            let clearWindow: (NSApplication.ModalResponse) -> Void = { _ in
                self.helperTrustVerificationAlertWindow = nil
            }

            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                self.helperTrustVerificationAlertWindow = alert.window
                alert.beginSheetModal(for: window, completionHandler: clearWindow)
            } else {
                self.helperTrustVerificationAlertWindow = alert.window
                clearWindow(alert.runModal())
            }
        }
    }
    func isHelperTrustVerificationFailureMessage(_ message: String) -> Bool {
        HelperConnectionSecurityPolicy.isTrustVerificationFailureMessage(message)
    }
    func isOperationNotPermitted(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.code == Int(EPERM) || nsError.code == 1 {
            return true
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("operation not permitted")
    }
    func diagnosticErrorDescription(for error: Error) -> String {
        let nsError = error as NSError
        var details = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]
        if let debugDescription = nsError.userInfo["NSDebugDescription"] as? String,
           !debugDescription.isEmpty {
            details.append("debug=\(debugDescription)")
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlying=\(underlyingError.domain):\(underlyingError.code)")
        }
        return "\(nsError.localizedDescription) [\(details.joined(separator: ", "))]"
    }
    func isLikelyBackgroundTaskPolicyBlock(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "SMAppServiceErrorDomain" && nsError.code == 1
    }
    func isRunningFromXcodeSession() -> Bool {
        #if DEBUG
        return Self.isRunningFromXcodeDevelopmentBuild()
        #else
        return false
        #endif
    }
    func presentOperationSummary(success: Bool, message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = success ? .informational : .warning
        alert.messageText = success ? String(localized: "app.helper.operation.success.title", table: "App") : String(localized: "app.helper.operation.failure.title", table: "App")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        presentAlert(alert)
    }
    func presentAlert(_ alert: NSAlert) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
