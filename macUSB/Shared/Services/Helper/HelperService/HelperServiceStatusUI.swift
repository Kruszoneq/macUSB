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
                    } else if snapshot.serviceStatus == .requiresApproval {
                        self.presentApprovalRequiredStatusAlert(detailsText: snapshot.detailedText)
                    } else {
                        let alert = NSAlert()
                        alert.icon = NSApp.applicationIconImage
                        alert.alertStyle = .warning
                        alert.messageText = String(localized: "Sprawdzenie statusu helpera zakończone niepowodzeniem")
                        alert.informativeText = String(localized: "Nie udało się potwierdzić gotowości helpera.")
                        alert.addButton(withTitle: String(localized: "OK"))
                        alert.addButton(withTitle: String(localized: "Szczegóły"))

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
            format: String(localized: "Status usługi: %@"),
            statusDescription(serviceStatus)
        )
        let serviceHealthy = serviceStatus == .enabled

        let locationLine: String
        let locationHealthy: Bool
        if isAppInstalledInApplications() {
            locationLine = String(localized: "Lokalizacja aplikacji: /Applications (OK)")
            locationHealthy = true
        } else {
            #if DEBUG
            if Self.isRunningFromXcodeDevelopmentBuild() {
                locationLine = String(localized: "Lokalizacja aplikacji: środowisko Xcode (bypass DEBUG)")
                locationHealthy = true
            } else {
                locationLine = String(localized: "Lokalizacja aplikacji: poza /Applications")
                locationHealthy = false
            }
            #else
            locationLine = String(localized: "Lokalizacja aplikacji: poza /Applications")
            locationHealthy = false
            #endif
        }

        PrivilegedOperationClient.shared.queryHealth(withTimeout: statusHealthTimeout) { ok, details in
            let xpcHealthValue = ok ? String(localized: "OK") : String(localized: "BŁĄD")
            let lines: [String] = [
                serviceStatusLine,
                String(
                    format: String(localized: "Mach service: %@"),
                    Self.machServiceName
                ),
                locationLine,
                String(
                    format: String(localized: "XPC health: %@"),
                    xpcHealthValue
                ),
                String(
                    format: String(localized: "Szczegóły: %@"),
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
        alert.messageText = String(localized: "Sprawdzenie statusu helpera zakończone pomyślnie")
        alert.informativeText = String(localized: "Helper działa prawidłowo i jest gotowy do pracy.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Szczegóły"))

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
        alert.messageText = String(localized: "Sprawdzenie statusu helpera zakończone wymaganym działaniem")
        alert.informativeText = String(localized: "Aby helper działał poprawnie, wymagane jest zezwolenie na działanie w tle w Ustawieniach systemowych.")
        alert.addButton(withTitle: String(localized: "Ustawienia systemowe"))
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Szczegóły"))

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
        alert.messageText = String(localized: "Szczegóły statusu helpera")
        alert.informativeText = detailsText
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }
    func presentStatusCheckingPanelIfNeeded() {
        guard statusCheckAlertWindow == nil else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Sprawdzanie statusu helpera")
        alert.informativeText = String(localized: "Trwa sprawdzanie gotowości helpera systemowego.")
        alert.addButton(withTitle: String(localized: "Sprawdzanie…"))
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
