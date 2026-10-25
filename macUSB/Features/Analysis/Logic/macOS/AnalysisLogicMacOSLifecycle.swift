import SwiftUI
import Foundation

extension AnalysisLogic {
    func forceTigerMultiDVDSelection() {
        MenuState.shared.lockLanguageChanges(reason: "manual_tiger_selection")
        cancelActiveImageAnalysisRun(reason: "manual Tiger Multi DVD selection")
        self.log("Tiger Multi DVD mode selected manually", workflow: .ppc)
        let fileURL = self.selectedFileUrl
        DispatchQueue.global(qos: .userInitiated).async {
            let resolvedRequirement = fileURL.flatMap { try? USBTargetCapacityRequirement.forSource(at: $0) }
            var mountPoint: String? = self.mountedDMGPath
            var effectiveSourceAppURL: URL? = nil
            if let url = fileURL {
                let ext = url.pathExtension.lowercased()
                if ext == "dmg" || ext == "iso" || ext == "cdr" {
                    if mountPoint == nil {
                        mountPoint = self.mountImageForPPC(dmgUrl: url)
                    }
                    if let mp = mountPoint {
                        effectiveSourceAppURL = URL(fileURLWithPath: mp).appendingPathComponent("Install")
                    }
                } else if ext == "app" {
                    effectiveSourceAppURL = url
                }
            }
            DispatchQueue.main.async {
                guard self.selectedFileUrl == fileURL else { return }
                withAnimation {
                    self.isAnalyzing = false
                    self.userSkippedAnalysis = true
                    self.recognizedVersion = "Mac OS X Tiger 10.4"
                    self.sourceAppURL = effectiveSourceAppURL
                    self.updateDetectedSystemIcon(from: effectiveSourceAppURL)
                    self.isBetaInstaller = false
                    self.mountedDMGPath = mountPoint
                    self.isSystemDetected = true
                    self.showUnsupportedMessage = false
                    self.showUSBSection = true
                    self.needsCodesign = false
                    self.isLegacyDetected = false
                    self.isRestoreLegacy = false
                    self.isCatalina = false
                    self.isSierra = false
                    self.isMavericks = false
                    self.isUnsupportedSierra = false
                    self.isPPC = true
                    self.createInstallMediaInspection = .notApplicable
                    self.macOSArchitectureBlockReason = nil
                    self.macOSRosettaRequirement = .notRequired
                    self.legacyArchInfo = nil
                    self.selectedDrive = nil
                    self.usbTargetReadiness = .noSelection
                    if let fileURL {
                        self.applySourceCapacityRequirement(resolvedRequirement, sourceURL: fileURL)
                    } else {
                        self.usbTargetCapacityRequirement = USBTargetCapacityRequirement.fallback()
                        self.shouldShowSourceSizeUnavailableAlert = true
                    }
                    self.resetLinuxDetectionState()
                    self.resetWindowsDetectionState()
                }
                let flags = [self.isPPC ? "isPPC" : nil].compactMap { $0 }.joined(separator: ", ")
                self.log("Tiger Multi DVD mode set: recognizedVersion=\(self.recognizedVersion). Flags: \(flags.isEmpty ? "none" : flags)", workflow: .ppc)
            }
        }
    }

    func resetAll() {
        cancelActiveImageAnalysisRun(reason: "full analysis state reset")
        let oldMount = self.mountedDMGPath
        if let path = oldMount {
            let task = Process()
            task.launchPath = "/usr/bin/hdiutil"
            task.arguments = ["detach", path, "-force"]
            try? task.run()
            task.waitUntilExit()
        }
        DispatchQueue.main.async {
            withAnimation {
                self.selectedFilePath = ""
                self.selectedFileUrl = nil
                self.recognizedVersion = ""
                self.sourceAppURL = nil
                self.detectedSystemIcon = nil
                self.isBetaInstaller = false
                self.mountedDMGPath = nil

                self.isAnalyzing = false
                self.isSystemDetected = false
                self.showUSBSection = false
                self.showUnsupportedMessage = false

                self.needsCodesign = true
                self.isLegacyDetected = false
                self.isRestoreLegacy = false
                self.isCatalina = false
                self.isSierra = false
                self.isMavericks = false
                self.isUnsupportedSierra = false
                self.isPPC = false
                self.createInstallMediaInspection = .notApplicable
                self.macOSArchitectureBlockReason = nil
                self.macOSRosettaRequirement = .notRequired
                self.legacyArchInfo = nil
                self.shouldShowAlreadyMountedSourceAlert = false
                self.userSkippedAnalysis = false
                self.shouldShowMavericksDialog = false
                self.usbTargetCapacityRequirement = nil
                self.shouldShowSourceSizeUnavailableAlert = false
                self.resetLinuxDetectionState()
                self.resetWindowsDetectionState()

                self.isMacOSCreateInstallMediaVolumeOverrideActive = false
                self.presentedUSBTargets = self.physicalUSBTargetsCache
                self.selectedDrive = nil

                self.usbTargetReadiness = .noSelection
            }
        }
    }

    // Call this from the UI when the user presses the "Przejdź dalej" button
    func recordProceedPressed() {
        self.log("User selected Continue. Selected target: \(self.selectedDrive?.url.path ?? "none"), source: \(self.sourceAppURL?.path ?? "none"), recognized: \(self.recognizedVersion)", workflow: selectedWorkflowForLogging)
    }
}
