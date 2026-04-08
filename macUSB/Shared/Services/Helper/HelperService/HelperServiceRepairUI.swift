import Foundation
import AppKit

extension HelperServiceManager {
    func markRepairStartIfPossible() -> Bool {
        coordinationQueue.sync {
            if repairInProgress {
                DispatchQueue.main.async {
                    self.presentOperationSummary(
                        success: false,
                        message: String(localized: "Trwa już naprawa helpera. Poczekaj na jej zakończenie.")
                    )
                }
                return false
            }
            repairInProgress = true
            return true
        }
    }

    func finishRepairFlow() {
        coordinationQueue.async {
            self.repairInProgress = false
        }
    }

    func reportHelperServiceEvent(_ message: String) {
        AppLogging.info(message, category: "HelperService")
        repairSinkLock.lock()
        let sink = repairProgressSink
        repairSinkLock.unlock()
        sink?(message)
    }

    func setRepairProgressSink(_ sink: ((String) -> Void)?) {
        repairSinkLock.lock()
        repairProgressSink = sink
        repairSinkLock.unlock()
    }

    func startRepairPresentation() {
        dismissRepairProgressAlertIfNeeded()
        repairTechnicalLogs.removeAll(keepingCapacity: true)
        appendRepairTechnicalLogLine("Rozpoczynanie operacji naprawy.")
        presentRepairProgressAlertIfNeeded()
        setRepairProgressSink { [weak self] message in
            DispatchQueue.main.async {
                self?.appendRepairTechnicalLogLine(message)
            }
        }
    }

    func finishRepairPresentation(success: Bool, message: String) {
        appendRepairTechnicalLogLine(message)
        dismissRepairProgressAlertIfNeeded()
        presentRepairSummaryAlert(success: success, message: message)
        setRepairProgressSink(nil)
    }

    private func presentRepairProgressAlertIfNeeded() {
        guard repairProgressAlertWindow == nil else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Naprawa helpera")
        alert.informativeText = String(localized: "Trwa odświeżanie rejestracji i połączenia helpera systemowego.")
        alert.addButton(withTitle: String(localized: "Naprawianie…"))
        alert.buttons.first?.isEnabled = false

        if let ownerWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            repairProgressAlertParentWindow = ownerWindow
            repairProgressAlertWindow = alert.window
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
        repairProgressAlertParentWindow = nil
        repairProgressAlertWindow = alertWindow
    }

    private func dismissRepairProgressAlertIfNeeded() {
        guard let alertWindow = repairProgressAlertWindow else { return }

        if let parentWindow = repairProgressAlertParentWindow,
           parentWindow.attachedSheet == alertWindow {
            parentWindow.endSheet(alertWindow, returnCode: .abort)
        }

        alertWindow.orderOut(nil)
        alertWindow.close()
        repairProgressAlertWindow = nil
        repairProgressAlertParentWindow = nil
    }

    private func presentRepairSummaryAlert(success: Bool, message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = success ? .informational : .warning

        if success {
            alert.messageText = String(localized: "Naprawa helpera zakończona pomyślnie")
            alert.informativeText = String(localized: "Rejestracja helpera i weryfikacja komunikacji zostały zakończone pomyślnie.")
            alert.addButton(withTitle: String(localized: "OK"))
            presentAlert(alert)
            return
        }

        alert.messageText = String(localized: "Naprawa helpera zakończona niepowodzeniem")
        alert.informativeText = String(localized: "Nie udało się przywrócić pełnej gotowości helpera. Szczegóły zapisano w logach diagnostycznych.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Szczegóły"))

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertSecondButtonReturn else { return }
            self.presentRepairDetailsAlert(fallbackMessage: message)
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func presentRepairDetailsAlert(fallbackMessage: String) {
        let details = repairTechnicalLogs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let technicalOutput = details.isEmpty ? fallbackMessage : details

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Szczegóły naprawy helpera")
        alert.informativeText = technicalOutput
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }

    private func appendRepairTechnicalLogLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let timestamp = repairLogFormatter.string(from: Date())
        repairTechnicalLogs.append("[\(timestamp)] \(trimmed)")
        if repairTechnicalLogs.count > 800 {
            repairTechnicalLogs.removeFirst(repairTechnicalLogs.count - 800)
        }
    }
}
