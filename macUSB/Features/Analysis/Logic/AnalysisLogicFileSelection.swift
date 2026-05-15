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
                self.logError("Nie udało się uruchomić odmontowania poprzedniego obrazu: \(mountPath) (\(error.localizedDescription))")
                return
            }

            if task.terminationStatus == 0 {
                self.log("Odmontowano poprzednio wybrany obraz: \(mountPath)")
            } else {
                let stderrText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if stderrText.isEmpty {
                    self.logError("Odmontowanie poprzedniego obrazu nie powiodło się: \(mountPath) (kod \(task.terminationStatus))")
                } else {
                    self.logError("Odmontowanie poprzedniego obrazu nie powiodło się: \(mountPath): \(stderrText)")
                }
            }
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        self.log("Odebrano przeciągnięcie pliku (providers=\(providers.count)). Szukam URL...")
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, _) in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    self.log("Przeciągnięto plik w formacie .\(url.pathExtension.lowercased())")
                    let ext = url.pathExtension.lowercased()
                    if ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" {
                        self.processDroppedURL(url)
                    }
                }
                else if let url = item as? URL {
                    self.log("Przeciągnięto plik w formacie .\(url.pathExtension.lowercased())")
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
            self.log("Wybrano plik w formacie .\(ext). Resetuję stan i przygotowuję analizę.")
            if ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" {
                self.cancelActiveImageAnalysisRun(reason: "Zmiana wybranego pliku podczas analizy")
                let previousMountedPath = self.mountedDMGPath
                withAnimation {
                    self.selectedFilePath = url.path
                    self.selectedFileUrl = url
                    self.recognizedVersion = ""
                    self.isSystemDetected = false
                    self.sourceAppURL = nil
                    self.detectedSystemIcon = nil
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
                    self.requiredUSBCapacityGB = nil
                    self.mountedDMGPath = nil
                    self.resetLinuxDetectionState()
                    self.resetWindowsDetectionState()
                }
                self.log("Lokalizacja wybranego pliku: \(url.path)")
                self.log("Źródło do rozpoznania wersji: \(url.path)")
                self.detachPreviousMountedImageAfterSelectionChange(previousMountedPath)
            }
        }
    }

    func applySelectedURLAndStartAnalysis(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" else {
            logError("Pominięto automatyczne podstawienie ścieżki. Nieobsługiwany format: .\(ext)")
            return
        }

        processDroppedURL(url)
        DispatchQueue.main.async { [weak self] in
            self?.startAnalysis()
        }
    }

    func selectDMGFile() {
        self.log("Otwieram panel wyboru pliku…")
        let p = NSOpenPanel()
        p.allowedContentTypes = [.diskImage, .applicationBundle]
        // Dodajemy obsługę .iso i .cdr, które nie mają jeszcze UTType w UniformTypeIdentifiers, więc rozszerzamy allowedFileTypes
        p.allowedFileTypes = ["dmg", "iso", "cdr", "app"]
        p.allowsMultipleSelection = false
        p.begin {
            if $0 == .OK, let url = p.url {
                let ext = url.pathExtension.lowercased()
                guard ext == "dmg" || ext == "iso" || ext == "cdr" || ext == "app" else { return }
                self.cancelActiveImageAnalysisRun(reason: "Wybrano nowy plik źródłowy")
                let previousMountedPath = self.mountedDMGPath
                withAnimation {
                    self.selectedFilePath = url.path
                    self.selectedFileUrl = url
                    self.recognizedVersion = ""
                    self.isSystemDetected = false
                    self.sourceAppURL = nil
                    self.detectedSystemIcon = nil
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
                    self.requiredUSBCapacityGB = nil
                    self.mountedDMGPath = nil
                    self.resetLinuxDetectionState()
                    self.resetWindowsDetectionState()
                }
                self.log("Wybrano plik w formacie .\(ext)")
                self.log("Lokalizacja wybranego pliku: \(url.path)")
                self.log("Źródło do rozpoznania wersji: \(url.path)")
                self.detachPreviousMountedImageAfterSelectionChange(previousMountedPath)
            } else {
                self.log("Anulowano wybór pliku")
            }
        }
    }
}
