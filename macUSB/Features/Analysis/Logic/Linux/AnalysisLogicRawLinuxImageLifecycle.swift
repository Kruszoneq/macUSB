import Foundation
import SwiftUI

extension AnalysisLogic {
    func forceRawLinuxImageSelection(_ sourceURL: URL) {
        cancelActiveImageAnalysisRun(reason: "Wybór surowego obrazu Linux .img")

        let standardizedURL = sourceURL.standardizedFileURL
        guard standardizedURL.pathExtension.lowercased() == "img" else {
            logError("Nie można wymusić rozpoznania Linux (.img) dla .\(standardizedURL.pathExtension.lowercased()).")
            return
        }

        InstallerSourceImageUnmountRegistry.shared.registerSourceImage(
            path: standardizedURL.path,
            family: .linux,
            mountHint: nil,
            reason: "linux_raw_img"
        )

        log("Ręcznie wybrano surowy obraz Linux .img (bez analizy pliku).")

        withAnimation {
            self.selectedFilePath = standardizedURL.path
            self.selectedFileUrl = standardizedURL
            self.isAnalyzing = false
            self.userSkippedAnalysis = true
            self.resetLinuxDetectionState()
            self.resetWindowsDetectionState()

            self.isLinuxDetected = true
            self.isLinuxDistributionRecognized = false
            self.linuxDisplayName = "Linux (.img)"
            self.linuxSourceURL = standardizedURL

            self.recognizedVersion = "Linux (.img)"
            self.sourceAppURL = nil
            self.detectedSystemIcon = loadLinuxDetectedSystemIcon(for: nil)
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
            log("Linux raw .img source size: \(fileSizeBytes) bytes (source=\(fileSizeSource))")
        } else if capacityResolution.usedFallback {
            log("Linux raw .img source size unavailable. Applying fallback USB threshold: \(capacityResolution.requiredCapacityGB) GB")
        }
        log("Linux raw .img required USB threshold: \(capacityResolution.requiredCapacityGB) GB")
        log("Ustawiono ręczne rozpoznanie Linux (.img): recognizedVersion=\(recognizedVersion), source=\(standardizedURL.path)")
    }
}
