import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AnalysisLogic {
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
                    self.resetLinuxDetectionState()
                }
                self.log("Lokalizacja wybranego pliku: \(url.path)")
                self.log("Źródło do rozpoznania wersji: \(url.path)")
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
                    self.resetLinuxDetectionState()
                }
                self.log("Wybrano plik w formacie .\(ext)")
                self.log("Lokalizacja wybranego pliku: \(url.path)")
                self.log("Źródło do rozpoznania wersji: \(url.path)")
            } else {
                self.log("Anulowano wybór pliku")
            }
        }
    }
}
