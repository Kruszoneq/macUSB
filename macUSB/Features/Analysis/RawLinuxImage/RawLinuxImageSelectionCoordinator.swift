import AppKit

@MainActor
final class RawLinuxImageSelectionCoordinator {
    static let shared = RawLinuxImageSelectionCoordinator()

    private var activeAlert: NSAlert?
    private var activePanel: NSOpenPanel?

    private init() {}

    func presentSelectionFlow() {
        let presentingWindow = NSApp.keyWindow ?? NSApp.mainWindow
        presentWarningAlert(attachedTo: presentingWindow) { [weak self] shouldContinue in
            guard shouldContinue else { return }
            DispatchQueue.main.async {
                self?.presentImagePicker(attachedTo: presentingWindow)
            }
        }
    }

    private func presentWarningAlert(attachedTo window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "app.raw_image.selection.warning.title", table: "App")
        alert.informativeText = String(localized: "app.raw_image.selection.warning.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.cancel", table: "App"))
        alert.addButton(withTitle: String(localized: "app.raw_image.selection.action.continue", table: "App"))
        activeAlert = alert

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            self.activeAlert = nil
            completion(response == .alertSecondButtonReturn)
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func presentImagePicker(attachedTo window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["iso", "img"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = String(localized: "app.raw_image.selection.picker.title", table: "App")
        panel.message = String(localized: "app.raw_image.selection.picker.message", table: "App")
        activePanel = panel

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            self.activePanel = nil
            guard response == .OK, let url = panel.url else {
                AppLogging.info("Raw Linux .img selection cancelled.", stage: .analysis, workflow: .raw)
                return
            }

            let standardizedURL = url.standardizedFileURL
            guard ["iso", "img"].contains(standardizedURL.pathExtension.lowercased()) else {
                AppLogging.error("Raw Linux image rejected: unsupported extension .\(standardizedURL.pathExtension.lowercased()).", stage: .analysis, workflow: .raw)
                return
            }

            AppLogging.info("Raw Linux .img selected: \(standardizedURL.path)", stage: .analysis, workflow: .raw)
            AnalysisSelectionHandoff.shared.setPendingRawLinuxImageURL(standardizedURL)
            NotificationCenter.default.post(name: .macUSBNavigateToAnalysis, object: nil)
            NotificationCenter.default.post(name: .macUSBApplyPendingRawLinuxImage, object: nil)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }
}
