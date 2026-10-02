import Foundation
import AppKit
import ServiceManagement

extension HelperServiceManager {
    func presentStatusAlert() {
        coordinationQueue.async {
            guard !self.statusCheckInProgress else {
                return
            }

            self.statusCheckInProgress = true

            DispatchQueue.main.async {
                self.presentStatusCheckingPanelIfNeeded()
            }

            self.evaluateStatus { snapshot in
                DispatchQueue.main.async {
                    self.dismissStatusCheckingPanelIfNeeded()

                    if snapshot.isHealthy {
                        self.presentHealthyStatusAlert(detailsText: snapshot.detailedText)
                    } else if self.isHelperTrustVerificationFailureMessage(snapshot.detailedText) {
                        self.presentHelperTrustVerificationFailureAlert()
                    } else if snapshot.serviceStatus == .requiresApproval {
                        self.presentApprovalRequiredStatusAlert(detailsText: snapshot.detailedText)
                    } else {
                        let alert = NSAlert()
                        alert.icon = NSApp.applicationIconImage
                        alert.alertStyle = .warning
                        alert.messageText = String(localized: "app.helper.status.failure.title", table: "App")
                        alert.informativeText = String(localized: "app.helper.status.failure.message", table: "App")
                        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
                        alert.addButton(withTitle: String(localized: "app.action.details", table: "App"))

                        let handler: (NSApplication.ModalResponse) -> Void = { response in
                            guard response == .alertSecondButtonReturn else { return }
                            self.presentStatusDetailsAlert(detailsText: snapshot.detailedText)
                        }

                        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                            alert.beginSheetModal(for: window, completionHandler: handler)
                        } else {
                            handler(alert.runModal())
                        }
                    }

                    self.coordinationQueue.async {
                        self.statusCheckInProgress = false
                    }
                }
            }
        }
    }
    func evaluateStatus(completion: @escaping (HelperStatusSnapshot) -> Void) {
        let serviceStatus = SMAppService.daemon(plistName: Self.daemonPlistName).status
        let serviceStatusLine = String(
            format: String(localized: "app.helper.status.service", table: "App"),
            statusDescription(serviceStatus)
        )
        let serviceHealthy = serviceStatus == .enabled

        let locationLine: String
        let locationHealthy: Bool
        if isAppInstalledInApplications() {
            locationLine = String(localized: "app.helper.status.location.applications", table: "App")
            locationHealthy = true
        } else {
            #if DEBUG
            if Self.isRunningFromXcodeDevelopmentBuild() {
                locationLine = "App location: Xcode environment (DEBUG bypass)"
                locationHealthy = true
            } else {
                locationLine = String(localized: "app.helper.status.location.outside_applications", table: "App")
                locationHealthy = false
            }
            #else
            locationLine = String(localized: "app.helper.status.location.outside_applications", table: "App")
            locationHealthy = false
            #endif
        }

        PrivilegedOperationClient.shared.queryHealth(
            withTimeout: statusHealthTimeout,
            presentsTrustFailureAlert: true
        ) { ok, details in
            let xpcHealthValue = ok ? String(localized: "app.action.ok", table: "App") : String(localized: "app.helper.status.error", table: "App")
            let lines: [String] = [
                serviceStatusLine,
                String(
                    format: String(localized: "app.helper.status.mach_service", table: "App"),
                    Self.machServiceName
                ),
                locationLine,
                String(
                    format: String(localized: "app.helper.status.xpc_health", table: "App"),
                    xpcHealthValue
                ),
                String(
                    format: String(localized: "app.helper.status.details", table: "App"),
                    details
                )
            ]

            let healthy = serviceHealthy && locationHealthy && ok
            completion(
                HelperStatusSnapshot(
                    isHealthy: healthy,
                    serviceStatus: serviceStatus,
                    detailedText: lines.joined(separator: "\n")
                )
            )
        }
    }
    func presentHealthyStatusAlert(detailsText: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "app.helper.status.success.title", table: "App")
        alert.informativeText = String(localized: "app.helper.status.success.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        alert.addButton(withTitle: String(localized: "app.action.details", table: "App"))

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertSecondButtonReturn else { return }
                DispatchQueue.main.async {
                    self.presentStatusDetailsAlert(detailsText: detailsText)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                presentStatusDetailsAlert(detailsText: detailsText)
            }
        }
    }
    func presentApprovalRequiredStatusAlert(detailsText: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "app.helper.status.approval.title", table: "App")
        alert.informativeText = String(localized: "app.helper.status.approval.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.system_settings", table: "App"))
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        alert.addButton(withTitle: String(localized: "app.action.details", table: "App"))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
                return
            }

            if response == .alertThirdButtonReturn {
                DispatchQueue.main.async {
                    self.presentStatusDetailsAlert(detailsText: detailsText)
                }
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }
    func presentStatusDetailsAlert(detailsText: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "app.helper.status.details.title", table: "App")
        alert.informativeText = detailsText
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        presentAlert(alert)
    }
    func presentStatusCheckingPanelIfNeeded() {
        guard statusCheckAlertWindow == nil else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "app.helper.status.checking.title", table: "App")
        alert.informativeText = String(localized: "app.helper.status.checking.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.helper.status.checking.action", table: "App"))
        alert.buttons.first?.isEnabled = false

        if let ownerWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            statusCheckAlertParentWindow = ownerWindow
            statusCheckAlertWindow = alert.window
            alert.beginSheetModal(for: ownerWindow, completionHandler: nil)
            return
        }

        let alertWindow = alert.window
        alertWindow.standardWindowButton(.closeButton)?.isHidden = true
        alertWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        alertWindow.standardWindowButton(.zoomButton)?.isHidden = true
        alertWindow.level = .floating
        alertWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        statusCheckAlertParentWindow = nil
        statusCheckAlertWindow = alertWindow
    }
    func dismissStatusCheckingPanelIfNeeded() {
        guard let alertWindow = statusCheckAlertWindow else { return }

        if let parentWindow = statusCheckAlertParentWindow,
           parentWindow.attachedSheet == alertWindow {
            parentWindow.endSheet(alertWindow, returnCode: .abort)
        }

        alertWindow.orderOut(nil)
        alertWindow.close()
        statusCheckAlertWindow = nil
        statusCheckAlertParentWindow = nil
    }
}
