import SwiftUI
import Foundation

extension AnalysisLogic {
    private typealias MountedImageReadResult = (
        mountedReadInfo: (String, String, URL, String)?,
        sourceAlreadyMountedPath: String?,
        mountedImagePath: String?
    )

    private func mountAndReadInfoWithSoftTimeout(
        dmgUrl: URL,
        detectPreMountedSource: Bool,
        timeoutSeconds: TimeInterval?
    ) -> (result: MountedImageReadResult?, didTimeout: Bool) {
        guard let timeoutSeconds, timeoutSeconds > 0 else {
            return (mountAndReadInfo(dmgUrl: dmgUrl, detectPreMountedSource: detectPreMountedSource), false)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var localResult: MountedImageReadResult?
        DispatchQueue.global(qos: .userInitiated).async {
            localResult = self.mountAndReadInfo(dmgUrl: dmgUrl, detectPreMountedSource: detectPreMountedSource)
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            self.log("Przekroczono soft-timeout mountAndReadInfo (\(Int(timeoutSeconds)) s) dla \(dmgUrl.lastPathComponent). Pomijam wynik montowania i przechodzę do fallbacku Linux (bsdtar).")
            return (nil, true)
        }

        return (localResult, false)
    }

    func startAnalysis() {
        cancelActiveImageAnalysisRun(reason: "Start nowej analizy")
        guard let url = selectedFileUrl else { return }
        self.stage("Analiza pliku — start")
        self.log("Rozpoczynam analizę pliku")
        self.log("Źródło pliku do odczytu wersji: \(url.path)")
        withAnimation { isAnalyzing = true }
        detectedSystemIcon = nil
        selectedDrive = nil; capacityCheckFinished = false
        showUSBSection = false; showUnsupportedMessage = false
        isUnsupportedSierra = false
        isPPC = false
        isMavericks = false
        shouldShowAlreadyMountedSourceAlert = false
        requiredUSBCapacityGB = nil
        resetLinuxDetectionState()
        resetWindowsDetectionState()

        let ext = url.pathExtension.lowercased()
        self.log("Wykryto rozszerzenie: \(ext)")
        if ext == "dmg" || ext == "iso" || ext == "cdr" {
            if ext == "iso" {
                InstallerSourceImageUnmountRegistry.shared.registerSourceImage(
                    path: url.path,
                    family: .windows,
                    reason: "analysis_iso_start"
                )
                InstallerSourceImageUnmountRegistry.shared.registerSourceImage(
                    path: url.path,
                    family: .linux,
                    reason: "analysis_iso_start"
                )
            }
            self.stage("Analiza obrazu (DMG/ISO/CDR) — start")
            self.log("Analiza obrazu (DMG/ISO/CDR): montowanie obrazu przez hdiutil (attach -plist -nobrowse -readonly), odczyt Info.plist z aplikacji oraz wykrywanie wersji i trybu instalacji.")
            let analysisRunID = self.beginImageAnalysisRun(sourceURL: url)
            let oldMountPath = self.mountedDMGPath
            DispatchQueue.global(qos: .userInitiated).async {
                if let path = oldMountPath {
                    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); task.arguments = ["detach", path, "-force"]; try? task.run(); task.waitUntilExit()
                }
                let shouldDetectAlreadyMountedSource = (ext == "cdr" || ext == "iso")
                let softTimeoutSeconds: TimeInterval? = shouldDetectAlreadyMountedSource ? 10 : nil
                let mountReadOutcome = self.mountAndReadInfoWithSoftTimeout(
                    dmgUrl: url,
                    detectPreMountedSource: shouldDetectAlreadyMountedSource,
                    timeoutSeconds: softTimeoutSeconds
                )
                let result = mountReadOutcome.result
                let mountReadTimedOut = mountReadOutcome.didTimeout
                DispatchQueue.main.async {
                    guard self.isImageAnalysisRunCurrent(analysisRunID) else {
                        self.logIgnoredStaleImageAnalysisCallback(analysisRunID, stage: "mountAndReadInfo")
                        return
                    }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.isAnalyzing = false
                        let mountedReadInfo = result?.mountedReadInfo
                        let sourceAlreadyMountedPath = result?.sourceAlreadyMountedPath
                        let mountedImagePath = result?.mountedImagePath
                        let sourceAlreadyMounted = sourceAlreadyMountedPath != nil
                        if let mountPath = sourceAlreadyMountedPath {
                            self.log("Wykryto, że wybrany obraz źródłowy jest już zamontowany: \(mountPath)")
                        }
                        if let (_, _, _, mp) = mountedReadInfo {
                            self.mountedDMGPath = mp
                        } else {
                            self.mountedDMGPath = mountedImagePath
                        }
                        if let (name, rawVer, appURL, _) = mountedReadInfo {
                            let friendlyVer = self.formatMarketingVersion(raw: rawVer, name: name)
                            var cleanName = name
                            cleanName = cleanName.replacingOccurrences(of: "Install ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "macOS ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "Mac OS X ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "OS X ", with: "")
                            let prefix = name.contains("macOS") ? "macOS" : (name.contains("OS X") ? "OS X" : "macOS")

                            self.recognizedVersion = "\(prefix) \(cleanName) \(friendlyVer)"
                            self.updateRequiredUSBCapacity(rawVersion: rawVer, name: name)
                            self.sourceAppURL = appURL
                            self.updateDetectedSystemIcon(from: appURL)

                            // Try to read ProductUserVisibleVersion from mounted image (Tiger/Leopard)
                            var userVisibleVersionFromMounted: String? = nil
                            if let mountPath = self.mountedDMGPath {
                                let sysVerPlist = URL(fileURLWithPath: mountPath).appendingPathComponent("System/Library/CoreServices/SystemVersion.plist")
                                if let data = try? Data(contentsOf: sysVerPlist),
                                   let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                                   let userVisible = dict["ProductUserVisibleVersion"] as? String {
                                    userVisibleVersionFromMounted = userVisible
                                }
                            }

                            let compatibilityApplied = self.applyMacosCompatibilityForMountedInstaller(
                                name: name,
                                rawVer: rawVer,
                                userVisibleVersionFromMounted: userVisibleVersionFromMounted
                            )
                            self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Rozpoznano instalator macOS z obrazu")
                            if !compatibilityApplied {
                                return
                            }
                        } else if sourceAlreadyMounted {
                            self.recognizedVersion = ""
                            self.sourceAppURL = nil
                            self.detectedSystemIcon = nil
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
                            self.userSkippedAnalysis = false
                            self.requiredUSBCapacityGB = nil
                            self.shouldShowAlreadyMountedSourceAlert = true
                            self.resetLinuxDetectionState()
                            self.resetWindowsDetectionState()
                            self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Analiza zatrzymana: obraz źródłowy był już zamontowany")
                            AppLogging.separator()
                        } else {
                            if ext == "iso" {
                                if mountReadTimedOut {
                                    self.log("Po soft-timeout mountAndReadInfo pomijam fallback Windows z mount-path i przechodzę do Linux fallback (bsdtar).")
                                }

                                if let mountedImagePath {
                                    self.log("Nie rozpoznano instalatora macOS. Przechodzę do procesu rozpoznawania Windows (z zamontowanego obrazu).")
                                    if let windowsResult = self.detectWindows(fromMountPath: mountedImagePath, sourceURL: url) {
                                        self.applyWindowsDetectionResult(
                                            windowsResult,
                                            sourceURL: url,
                                            mountedImagePath: mountedImagePath
                                        )
                                        self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Rozpoznano obraz Windows z zamontowanego źródła")
                                        return
                                    }

                                    self.captureLinuxAttachSessionIfNeeded(sourceURL: url, reason: "linux_fallback_entry")
                                    self.log("Nie rozpoznano instalatora macOS/Windows. Przechodzę do procesu rozpoznawania Linuxa (z zamontowanego obrazu).")
                                    if let linuxResult = self.detectLinux(fromMountPath: mountedImagePath, sourceURL: url) {
                                        self.applyLinuxDetectionResult(linuxResult, sourceURL: url, mountedImagePath: mountedImagePath)
                                        self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Rozpoznano obraz Linux z zamontowanego źródła")
                                        return
                                    }
                                }

                                self.captureLinuxAttachSessionIfNeeded(sourceURL: url, reason: "linux_fallback_entry")
                                self.log("Nie rozpoznano instalatora macOS/Windows. Przechodzę do procesu rozpoznawania Linuxa przez bsdtar (bez montowania).")
                                self.isAnalyzing = true
                                DispatchQueue.global(qos: .userInitiated).async {
                                    let linuxResult = self.detectLinuxFromArchive(sourceURL: url)
                                    DispatchQueue.main.async {
                                        guard self.isImageAnalysisRunCurrent(analysisRunID) else {
                                            self.logIgnoredStaleImageAnalysisCallback(analysisRunID, stage: "detectLinuxFromArchive")
                                            return
                                        }
                                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                            defer { self.isAnalyzing = false }

                                            if let linuxResult {
                                                let mountPathForFallback = self.mountedDMGPath
                                                self.applyLinuxDetectionResult(linuxResult, sourceURL: url, mountedImagePath: mountPathForFallback)
                                                self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Rozpoznano obraz Linux przez bsdtar")
                                                return
                                            }

                                            self.log("Nie wykryto wiarygodnych sygnałów Linuxa. Kończę analizę jako nierozpoznaną.")
                                            self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Brak sygnałów Linuxa po fallbacku bsdtar")
                                            self.applyUnrecognizedInstallerState()
                                        }
                                    }
                                }
                                return
                            }

                            self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Brak rozpoznania instalatora dla obrazu")
                            self.applyUnrecognizedInstallerState()
                        }
                    }
                }
            }
        }
        else if ext == "app" {
            self.stage("Analiza aplikacji (.app) — start")
            self.log("Analiza aplikacji (.app): odczyt Info.plist (CFBundleDisplayName, CFBundleShortVersionString) oraz wykrywanie wersji i trybu instalacji.")
            self.log("Źródło pliku do odczytu wersji: \(url.path)")
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.readAppInfo(appUrl: url)
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.isAnalyzing = false
                        self.mountedDMGPath = nil
                        if let (name, rawVer, appURL) = result {
                            let friendlyVer = self.formatMarketingVersion(raw: rawVer, name: name)
                            var cleanName = name
                            cleanName = cleanName.replacingOccurrences(of: "Install ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "macOS ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "Mac OS X ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "OS X ", with: "")
                            let prefix = name.contains("macOS") ? "macOS" : (name.contains("OS X") ? "OS X" : "macOS")

                            self.recognizedVersion = "\(prefix) \(cleanName) \(friendlyVer)"
                            self.updateRequiredUSBCapacity(rawVersion: rawVer, name: name)
                            self.sourceAppURL = appURL
                            self.updateDetectedSystemIcon(from: appURL)

                            if !self.applyMacosCompatibilityForAppInstaller(name: name, rawVer: rawVer) {
                                return
                            }
                        } else {
                            self.applyUnrecognizedInstallerState()
                        }
                    }
                }
            }
        }
    }
}
