import SwiftUI
import Foundation

extension AnalysisLogic {
    func forceTigerMultiDVDSelection() {
        self.log("Ręcznie wybrano tryb Tiger Multi DVD")
        let fileURL = self.selectedFileUrl
        DispatchQueue.global(qos: .userInitiated).async {
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
                withAnimation {
                    self.isAnalyzing = false
                    self.userSkippedAnalysis = true
                    self.recognizedVersion = "Mac OS X Tiger 10.4"
                    self.sourceAppURL = effectiveSourceAppURL
                    self.updateDetectedSystemIcon(from: effectiveSourceAppURL)
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
                    self.legacyArchInfo = nil
                    self.selectedDrive = nil
                    self.capacityCheckFinished = false
                    self.requiredUSBCapacityGB = 16
                    self.resetLinuxDetectionState()
                }
                let flags = [self.isPPC ? "isPPC" : nil].compactMap { $0 }.joined(separator: ", ")
                self.log("Ustawiono Tiger Multi DVD: recognizedVersion=\(self.recognizedVersion). Flagi: \(flags.isEmpty ? "brak" : flags)")
            }
        }
    }

    func resetAll() {
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
                self.legacyArchInfo = nil
                self.shouldShowAlreadyMountedSourceAlert = false
                self.userSkippedAnalysis = false
                self.shouldShowMavericksDialog = false
                self.requiredUSBCapacityGB = nil
                self.resetLinuxDetectionState()

                self.availableDrives = []
                self.selectedDrive = nil
                self.hasUnreadableExternalUSBMedia = false
                self.unreadableExternalUSBMediaCount = 0
                self.lastUnreadableUSBDetectionDate = .distantPast
                self.isUnreadableUSBDetectionRunning = false

                self.isCapacitySufficient = false
                self.capacityCheckFinished = false
            }
        }
    }

    // Call this from the UI when the user presses the "Przejdź dalej" button
    func recordProceedPressed() {
        self.log("Użytkownik nacisnął przycisk 'Przejdź dalej'. Wybrany nośnik: \(self.selectedDrive?.url.path ?? "brak"), źródło: \(self.sourceAppURL?.path ?? "brak"), rozpoznano: \(self.recognizedVersion)")
    }
}
