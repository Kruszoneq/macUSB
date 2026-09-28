import Foundation
import SwiftUI

extension AnalysisLogic {
    func forceRawLinuxImageSelection(_ sourceURL: URL) {
        cancelActiveImageAnalysisRun(reason: "raw .iso/.img image selection")

        let standardizedURL = sourceURL.standardizedFileURL
        let sourceExtension = standardizedURL.pathExtension.lowercased()
        guard ["iso", "img"].contains(sourceExtension) else {
            logRawError("Cannot enable raw image writing for .\(sourceExtension).")
            return
        }
        MenuState.shared.lockLanguageChanges(reason: "raw_linux_selection")

        logRaw("Raw .iso/.img image selected manually without file analysis.")

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
            self.shouldShowSourceSizeUnavailableAlert = false
        }

        applySourceCapacityRequirement(
            try? USBTargetCapacityRequirement.forSource(at: standardizedURL),
            sourceURL: standardizedURL
        )
        logRaw("Manual raw image writing configured: recognizedVersion=\(recognizedVersion), source=\(standardizedURL.path)")
    }
}
