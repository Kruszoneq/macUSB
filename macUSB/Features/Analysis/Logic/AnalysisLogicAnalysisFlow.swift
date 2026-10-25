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
            self.logLinux("mountAndReadInfo soft timeout exceeded (\(Int(timeoutSeconds)) s) for \(dmgUrl.lastPathComponent). Skipping the mount result and continuing with Linux bsdtar fallback.")
            return (nil, true)
        }

        return (localResult, false)
    }

    func startAnalysis() {
        cancelActiveImageAnalysisRun(reason: "starting new analysis")
        guard let url = selectedFileUrl else { return }
        MenuState.shared.lockLanguageChanges(reason: "analysis_started")
        self.stage("File analysis started")
        AppLogging.info("Starting file analysis", stage: .analysis)
        AppLogging.info("Source file for version lookup: \(url.path)", stage: .analysis)
        withAnimation { isAnalyzing = true }
        detectedSystemIcon = nil
        isBetaInstaller = false
        selectedDrive = nil; usbTargetReadiness = .noSelection
        showUSBSection = false; showUnsupportedMessage = false
        isUnsupportedSierra = false
        isPPC = false
        isMavericks = false
        createInstallMediaInspection = .notApplicable
        macOSArchitectureBlockReason = nil
        macOSRosettaRequirement = .notRequired
        shouldShowAlreadyMountedSourceAlert = false
        usbTargetCapacityRequirement = nil
        shouldShowSourceSizeUnavailableAlert = false
        resetLinuxDetectionState()
        resetWindowsDetectionState()

        let ext = url.pathExtension.lowercased()
        self.log("Detected extension: \(ext)")
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
            self.stage("Image analysis (DMG/ISO/CDR) started")
            self.log("Image analysis (DMG/ISO/CDR): attaching with hdiutil (attach -plist -nobrowse -readonly), reading app Info.plist, and detecting the version and installation mode.")
            let analysisRunID = self.beginImageAnalysisRun(sourceURL: url)
            let oldMountPath = self.mountedDMGPath
            DispatchQueue.global(qos: .userInitiated).async {
                let resolvedRequirement = try? USBTargetCapacityRequirement.forSource(at: url)
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
                            self.log("Selected source image is already mounted: \(mountPath)")
                        }
                        if let (_, _, _, mp) = mountedReadInfo {
                            self.mountedDMGPath = mp
                        } else {
                            self.mountedDMGPath = mountedImagePath
                        }
                        if let (name, rawVer, appURL, _) = mountedReadInfo {
                            self.recognizedVersion = self.formatDetectedMacOSName(rawVersion: rawVer, name: name)
                            self.isBetaInstaller = self.detectBetaInstaller(name: name, appURL: appURL)
                            self.sourceAppURL = appURL
                            self.updateDetectedSystemIcon(from: appURL)

                            let architectureInspection = self.inspectMacOSInstallerApp(at: appURL)
                            guard self.applyMacOSArchitecturePreflight(
                                inspection: architectureInspection,
                                name: name,
                                rawVersion: rawVer
                            ) else {
                                self.completeImageAnalysisRunIfCurrent(
                                    analysisRunID,
                                    reason: "macOS installer blocked by architecture compatibility"
                                )
                                return
                            }

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
                            self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "macOS installer recognized from image")
                            if !compatibilityApplied {
                                return
                            }
                            self.applySourceCapacityRequirement(
                                resolvedRequirement,
                                sourceURL: url,
                                macOSMajorVersion: self.marketingMajorVersion(raw: rawVer, name: name)
                            )
                        } else if sourceAlreadyMounted {
                            self.recognizedVersion = ""
                            self.sourceAppURL = nil
                            self.detectedSystemIcon = nil
                            self.isBetaInstaller = false
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
                            self.usbTargetCapacityRequirement = nil
                            self.shouldShowAlreadyMountedSourceAlert = true
                            self.resetLinuxDetectionState()
                            self.resetWindowsDetectionState()
                            self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "analysis stopped: source image was already mounted")
                            AppLogging.separator(stage: .analysis)
                        } else {
                            if ext == "iso" {
                                if mountReadTimedOut {
                                    self.logLinux("After the mountAndReadInfo soft timeout, skipping mounted Windows fallback and continuing with Linux bsdtar fallback.")
                                }

                                if let mountedImagePath {
                                    self.logWindows("macOS installer not recognized. Starting Windows detection from the mounted image.")
                                    if let windowsResult = self.detectWindows(fromMountPath: mountedImagePath, sourceURL: url) {
                                        self.applyWindowsDetectionResult(
                                            windowsResult,
                                            sourceURL: url,
                                            mountedImagePath: mountedImagePath
                                        )
                                        self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Windows image recognized from mounted source")
                                        return
                                    }

                                    self.captureLinuxAttachSessionIfNeeded(sourceURL: url, reason: "linux_fallback_entry")
                                    self.logLinux("macOS and Windows installers not recognized. Starting Linux detection from the mounted image.")
                                    if let linuxResult = self.detectLinux(fromMountPath: mountedImagePath, sourceURL: url) {
                                        self.applyLinuxDetectionResult(linuxResult, sourceURL: url, mountedImagePath: mountedImagePath)
                                        self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Linux image recognized from mounted source")
                                        return
                                    }
                                }

                                self.captureLinuxAttachSessionIfNeeded(sourceURL: url, reason: "linux_fallback_entry")
                                self.logLinux("macOS and Windows installers not recognized. Starting Linux detection with bsdtar without mounting.")
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
                                                self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "Linux image recognized by bsdtar")
                                                return
                                            }

                                            self.logLinux("No reliable Linux markers found. Finishing analysis as unrecognized.")
                                            self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "no Linux markers after bsdtar fallback")
                                            self.applyUnrecognizedInstallerState()
                                        }
                                    }
                                }
                                return
                            }

                            self.completeImageAnalysisRunIfCurrent(analysisRunID, reason: "no installer recognized in image")
                            self.applyUnrecognizedInstallerState()
                        }
                    }
                }
            }
        }
        else if ext == "app" {
            self.stage("App analysis (.app) started", workflow: .macos)
            self.logMacOS("App analysis (.app): reading Info.plist, checking installer payload (createinstallmedia/InstallESD.dmg), and detecting the version and installation mode.")
            self.logMacOS("Source file for version lookup: \(url.path)")
            DispatchQueue.global(qos: .userInitiated).async {
                let inspection = self.inspectMacOSInstallerApp(at: url)
                let resolvedRequirement = try? USBTargetCapacityRequirement.forSource(at: url)
                DispatchQueue.main.async {
                    guard self.selectedFileUrl == url else { return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.isAnalyzing = false
                        self.mountedDMGPath = nil
                        self.logMacOS("macOS installer app validation: \(inspection.logSummary)")
                        if let (name, rawVer, appURL) = inspection.appInfo {
                            self.recognizedVersion = self.formatDetectedMacOSName(rawVersion: rawVer, name: name)
                            self.isBetaInstaller = self.detectBetaInstaller(name: name, appURL: appURL)
                            self.sourceAppURL = appURL
                            self.updateDetectedSystemIcon(from: appURL)

                            guard self.applyMacOSArchitecturePreflight(
                                inspection: inspection,
                                name: name,
                                rawVersion: rawVer
                            ) else {
                                return
                            }

                            if !self.applyMacosCompatibilityForAppInstaller(name: name, rawVer: rawVer) {
                                return
                            }
                            self.applySourceCapacityRequirement(
                                resolvedRequirement,
                                sourceURL: url,
                                macOSMajorVersion: self.marketingMajorVersion(raw: rawVer, name: name)
                            )
                        } else {
                            self.applyInvalidMacOSInstallerAppState(reason: inspection.decisionReason)
                        }
                    }
                }
            }
        }
    }
}
