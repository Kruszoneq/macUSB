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
        alert.messageText = String(localized: "raw_linux_img.alert.title")
        alert.informativeText = String(localized: "raw_linux_img.alert.message")
        alert.addButton(withTitle: String(localized: "Anuluj"))
        alert.addButton(withTitle: String(localized: "raw_linux_img.alert.continue_button"))
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
        panel.allowedFileTypes = ["img"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = String(localized: "raw_linux_img.panel.title")
        panel.message = String(localized: "raw_linux_img.panel.message")
        activePanel = panel

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            self.activePanel = nil
            guard response == .OK, let url = panel.url else {
                AppLogging.info("Anulowano wybór surowego obrazu Linux .img.", category: "FileAnalysis")
                return
            }

            let standardizedURL = url.standardizedFileURL
            guard standardizedURL.pathExtension.lowercased() == "img" else {
                AppLogging.error("Pominięto surowy obraz Linux: nieobsługiwane rozszerzenie .\(standardizedURL.pathExtension.lowercased()).", category: "FileAnalysis")
                return
            }

            AppLogging.info("Wybrano surowy obraz Linux .img: \(standardizedURL.path)", category: "FileAnalysis")
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
