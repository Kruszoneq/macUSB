import Foundation
import AppKit

extension HelperServiceManager {
    func markRepairStartIfPossible() -> Bool {
        coordinationQueue.sync {
            if repairInProgress {
                DispatchQueue.main.async {
                    self.presentOperationSummary(
                        success: false,
                        message: String(localized: "app.helper.repair.already_running.message", table: "App")
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

    func reportHelperServiceEvent(
        _ message: String,
        stage: AppLogging.Stage,
        workflow: AppLogging.Workflow? = nil,
        isError: Bool = false
    ) {
        if isError {
            AppLogging.error(message, stage: stage, workflow: workflow)
        } else {
            AppLogging.info(message, stage: stage, workflow: workflow)
        }
        repairSinkLock.lock()
        let sink = repairProgressSink
        repairSinkLock.unlock()
        sink?(message)
    }

    func reportHelperRepairEvent(_ message: String, isError: Bool = false) {
        reportHelperServiceEvent(message, stage: .helper, workflow: .repair, isError: isError)
    }

    func setRepairProgressSink(_ sink: ((String) -> Void)?) {
        repairSinkLock.lock()
        repairProgressSink = sink
        repairSinkLock.unlock()
    }

    func startRepairPresentation() {
        dismissRepairProgressAlertIfNeeded()
        repairTechnicalLogs.removeAll(keepingCapacity: true)
        appendRepairTechnicalLogLine("Helper repair started.")
        presentRepairProgressAlertIfNeeded()
        setRepairProgressSink { [weak self] message in
            DispatchQueue.main.async {
                self?.appendRepairTechnicalLogLine(message)
            }
        }
    }

    func finishRepairPresentation(success: Bool, message: String) {
        appendRepairTechnicalLogLine("Helper repair finished: success=\(success).")
        let ownerWindow = repairProgressAlertParentWindow
        dismissRepairProgressAlertIfNeeded()
        if !success, isHelperTrustVerificationFailureMessage(message) {
            presentHelperTrustVerificationFailureAlert()
            setRepairProgressSink(nil)
            return
        }
        presentRepairSummaryAlert(success: success, message: message, ownerWindow: ownerWindow)
        setRepairProgressSink(nil)
    }

    private func repairAlertOwnerWindow() -> NSWindow? {
        var window = NSApp.keyWindow ?? NSApp.mainWindow
        while let parent = window?.sheetParent {
            window = parent
        }
        return window
    }

    private func presentRepairProgressAlertIfNeeded() {
        guard repairProgressAlertWindow == nil else { return }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "app.helper.repair.running.title", table: "App")
        alert.informativeText = String(localized: "app.helper.repair.running.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.helper.repair.running.action", table: "App"))
        alert.buttons.first?.isEnabled = false

        if let ownerWindow = repairAlertOwnerWindow() {
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

    private func presentRepairSummaryAlert(success: Bool, message: String, ownerWindow: NSWindow?) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = success ? .informational : .warning

        if success {
            alert.messageText = String(localized: "app.helper.repair.success.title", table: "App")
            alert.informativeText = String(localized: "app.helper.repair.success.message", table: "App")
            alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
            presentRepairAlert(alert, ownerWindow: ownerWindow)
            return
        }

        alert.messageText = String(localized: "app.helper.repair.failure.title", table: "App")
        alert.informativeText = String(localized: "app.helper.repair.failure.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        alert.addButton(withTitle: String(localized: "app.action.details", table: "App"))

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertSecondButtonReturn else { return }
            // Finish dismissing the summary before attaching another sheet to its owner.
            DispatchQueue.main.async {
                self.presentRepairDetailsAlert(fallbackMessage: message, ownerWindow: ownerWindow)
            }
        }

        if let ownerWindow {
            alert.beginSheetModal(for: ownerWindow, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func presentRepairDetailsAlert(fallbackMessage: String, ownerWindow: NSWindow?) {
        let details = repairTechnicalLogs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let technicalOutput = details.isEmpty ? fallbackMessage : details

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "app.helper.repair.details.title", table: "App")
        alert.informativeText = String(localized: "app.helper.repair.failure.message", table: "App")
        alert.accessoryView = makeRepairLogScrollView(technicalOutput)
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        presentRepairAlert(alert, ownerWindow: ownerWindow)
    }

    private func presentRepairAlert(_ alert: NSAlert, ownerWindow: NSWindow?) {
        if let ownerWindow {
            alert.beginSheetModal(for: ownerWindow, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func makeRepairLogScrollView(_ output: String) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = output
        scrollView.documentView = textView
        return scrollView
    }

    private func appendRepairTechnicalLogLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let timestamp = repairLogFormatter.string(from: Date())
        let prefix = "[\(timestamp)] [HELPER_REPAIR]"
        repairTechnicalLogs.append(
            trimmed.components(separatedBy: "\n")
                .map { "\(prefix) \($0)" }
                .joined(separator: "\n")
        )
        if repairTechnicalLogs.count > 800 {
            repairTechnicalLogs.removeFirst(repairTechnicalLogs.count - 800)
        }
    }
}
