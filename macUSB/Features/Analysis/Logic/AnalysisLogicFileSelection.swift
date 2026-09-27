import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AnalysisLogic {
    private func detachPreviousMountedImageAfterSelectionChange(_ mountPath: String?) {
        guard let mountPath, !mountPath.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            task.arguments = ["detach", mountPath, "-force"]
            let errorPipe = Pipe()
            task.standardError = errorPipe

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                self.logUnclassifiedError("Failed to start detaching the previous image: \(mountPath) (\(error.localizedDescription))")
                return
            }

            if task.terminationStatus == 0 {
                self.logUnclassified("Detached previously selected image: \(mountPath)")
            } else {
                let stderrText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if stderrText.isEmpty {
                    self.logUnclassifiedError("Detaching the previous image failed: \(mountPath) (exit code \(task.terminationStatus))")
                } else {
                    self.logUnclassifiedError("Detaching the previous image failed: \(mountPath): \(stderrText)")
                }
            }
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        self.logUnclassified("Received file drop (providers=\(providers.count)). Looking for URL...")
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, _) in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    self.logUnclassified("Dropped file with extension .\(url.pathExtension.lowercased())")
                    let ext = url.pathExtension.lowercased()
                    if ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" {
                        self.processDroppedURL(url)
                    }
                }
                else if let url = item as? URL {
                    self.logUnclassified("Dropped file with extension .\(url.pathExtension.lowercased())")
                    let ext = url.pathExtension.lowercased()
                    if ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" {
                        self.processDroppedURL(url)
                    }
                }
            }
            return true
        }
        return false
    }

    func processDroppedURL(_ url: URL) {
        DispatchQueue.main.async {
            let ext = url.pathExtension.lowercased()
            self.logUnclassified("Selected file with extension .\(ext). Resetting state and preparing analysis.")
            if ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" {
                self.cancelActiveImageAnalysisRun(reason: "source file changed during analysis")
                let previousMountedPath = self.mountedDMGPath
                withAnimation {
                    self.selectedFilePath = url.path
                    self.selectedFileUrl = url
                    self.recognizedVersion = ""
                    self.isSystemDetected = false
                    self.sourceAppURL = nil
                    self.detectedSystemIcon = nil
                    self.isBetaInstaller = false
                    self.selectedDrive = nil
                    self.capacityCheckFinished = false
                    self.showUSBSection = false
                    self.showUnsupportedMessage = false
                    self.isSierra = false
                    self.isMavericks = false
                    self.isUnsupportedSierra = false
                    self.isPPC = false
                    self.legacyArchInfo = nil
                    self.userSkippedAnalysis = false
                    self.shouldShowMavericksDialog = false
                    self.usbTargetCapacityRequirement = nil
                    self.shouldShowSourceSizeUnavailableAlert = false
                    self.mountedDMGPath = nil
                    self.resetLinuxDetectionState()
                    self.resetWindowsDetectionState()
                }
                self.logUnclassified("Selected file path: \(url.path)")
                self.logUnclassified("Source for version detection: \(url.path)")
                self.detachPreviousMountedImageAfterSelectionChange(previousMountedPath)
            }
        }
    }

    func applySelectedURLAndStartAnalysis(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" else {
            logUnclassifiedError("Automatic path handoff skipped. Unsupported format: .\(ext)")
            return
        }

        processDroppedURL(url)
        DispatchQueue.main.async { [weak self] in
            self?.startAnalysis()
        }
    }

    func selectDMGFile() {
        self.logUnclassified("Opening file selection panel…")
        let p = NSOpenPanel()
        p.allowedContentTypes = [.diskImage, .applicationBundle]
        // Dodajemy obsługę .iso i .cdr, które nie mają jeszcze UTType w UniformTypeIdentifiers, więc rozszerzamy allowedFileTypes
        p.allowedFileTypes = ["dmg", "iso", "cdr", "app"]
        p.allowsMultipleSelection = false
        p.begin {
            if $0 == .OK, let url = p.url {
                let ext = url.pathExtension.lowercased()
                guard ext == "dmg" || ext == "iso" || ext == "cdr" || ext == "app" else { return }
                self.cancelActiveImageAnalysisRun(reason: "selected a new source file")
                let previousMountedPath = self.mountedDMGPath
                withAnimation {
                    self.selectedFilePath = url.path
                    self.selectedFileUrl = url
                    self.recognizedVersion = ""
                    self.isSystemDetected = false
                    self.sourceAppURL = nil
                    self.detectedSystemIcon = nil
                    self.isBetaInstaller = false
                    self.selectedDrive = nil
                    self.capacityCheckFinished = false
                    self.showUSBSection = false
                    self.showUnsupportedMessage = false
                    self.isSierra = false
                    self.isMavericks = false
                    self.isUnsupportedSierra = false
                    self.isPPC = false
                    self.legacyArchInfo = nil
                    self.userSkippedAnalysis = false
                    self.shouldShowMavericksDialog = false
                    self.usbTargetCapacityRequirement = nil
                    self.shouldShowSourceSizeUnavailableAlert = false
                    self.mountedDMGPath = nil
                    self.resetLinuxDetectionState()
                    self.resetWindowsDetectionState()
                }
                self.logUnclassified("Selected file with extension .\(ext)")
                self.logUnclassified("Selected file path: \(url.path)")
                self.logUnclassified("Source for version detection: \(url.path)")
                self.detachPreviousMountedImageAfterSelectionChange(previousMountedPath)
            } else {
                self.logUnclassified("File selection cancelled")
            }
        }
    }
}
