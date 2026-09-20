import Foundation
import SwiftUI

extension AnalysisLogic {
    func forceRawLinuxImageSelection(_ sourceURL: URL) {
        cancelActiveImageAnalysisRun(reason: "Wybór surowego obrazu .iso/.img")

        let standardizedURL = sourceURL.standardizedFileURL
        let sourceExtension = standardizedURL.pathExtension.lowercased()
        guard ["iso", "img"].contains(sourceExtension) else {
            logError("Nie można wymusić surowego zapisu dla .\(sourceExtension).")
            return
        }
        MenuState.shared.lockLanguageChanges(reason: "raw_linux_selection")

        log("Ręcznie wybrano surowy obraz .iso/.img (bez analizy pliku).")

        withAnimation {
            self.selectedFilePath = standardizedURL.path
            self.selectedFileUrl = standardizedURL
            self.isAnalyzing = false
            self.userSkippedAnalysis = true
            self.resetLinuxDetectionState()
            self.resetWindowsDetectionState()

            self.isLinuxDetected = true
            self.isRawImageSelection = true
            self.isLinuxDistributionRecognized = false
            self.linuxDisplayName = standardizedURL.lastPathComponent
            self.linuxSourceURL = standardizedURL

            self.recognizedVersion = standardizedURL.lastPathComponent
            self.sourceAppURL = nil
            self.detectedSystemIcon = nil
            self.mountedDMGPath = nil

            self.isSystemDetected = true
            self.showUnsupportedMessage = false
            self.showUSBSection = false

            self.needsCodesign = true
            self.isLegacyDetected = false
            self.isRestoreLegacy = false
            self.isCatalina = false
            self.isSierra = false
            self.isMavericks = false
            self.isUnsupportedSierra = false
            self.isPPC = false
            self.legacyArchInfo = nil
            self.selectedDrive = nil
            self.capacityCheckFinished = false
            self.shouldShowMavericksDialog = false
            self.shouldShowAlreadyMountedSourceAlert = false
        }

        let capacityResolution = resolveRequiredUSBCapacityForImageSource(standardizedURL)
        requiredUSBCapacityGB = capacityResolution.requiredCapacityGB
        if let fileSizeBytes = capacityResolution.sourceFileSizeBytes,
           let fileSizeSource = capacityResolution.sourceFileSizeSource {
            log("Raw image source size: \(fileSizeBytes) bytes (source=\(fileSizeSource))")
        } else if capacityResolution.usedFallback {
            log("Raw image source size unavailable. Applying fallback USB threshold: \(capacityResolution.requiredCapacityGB) GB")
        }
        log("Raw image required USB threshold: \(capacityResolution.requiredCapacityGB) GB")
        log("Ustawiono ręczny zapis surowego obrazu: recognizedVersion=\(recognizedVersion), source=\(standardizedURL.path)")
    }
}
