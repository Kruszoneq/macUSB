import SwiftUI
import Foundation

extension AnalysisLogic {
    func startAnalysis() {
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

        let ext = url.pathExtension.lowercased()
        self.log("Wykryto rozszerzenie: \(ext)")
        if ext == "dmg" || ext == "iso" || ext == "cdr" {
            self.stage("Analiza obrazu (DMG/ISO/CDR) — start")
            self.log("Analiza obrazu (DMG/ISO/CDR): montowanie obrazu przez hdiutil (attach -plist -nobrowse -readonly), odczyt Info.plist z aplikacji oraz wykrywanie wersji i trybu instalacji.")
            let oldMountPath = self.mountedDMGPath
            DispatchQueue.global(qos: .userInitiated).async {
                if let path = oldMountPath {
                    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); task.arguments = ["detach", path, "-force"]; try? task.run(); task.waitUntilExit()
                }
                let shouldDetectAlreadyMountedSource = (ext == "cdr" || ext == "iso")
                let result = self.mountAndReadInfo(dmgUrl: url, detectPreMountedSource: shouldDetectAlreadyMountedSource)
                DispatchQueue.main.async {
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

                            if !self.applyMacosCompatibilityForMountedInstaller(name: name, rawVer: rawVer, userVisibleVersionFromMounted: userVisibleVersionFromMounted) {
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
                            AppLogging.separator()
                        } else {
                            if ext == "iso" || ext == "cdr" {
                                if let mountedImagePath {
                                    self.log("Nie rozpoznano instalatora macOS. Przechodzę do procesu rozpoznawania Linuxa (z zamontowanego obrazu).")
                                    if let linuxResult = self.detectLinux(fromMountPath: mountedImagePath, sourceURL: url) {
                                        self.applyLinuxDetectionResult(linuxResult, sourceURL: url, mountedImagePath: mountedImagePath)
                                        return
                                    }
                                }

                                self.log("Nie rozpoznano instalatora macOS. Przechodzę do procesu rozpoznawania Linuxa przez bsdtar (bez montowania).")
                                self.isAnalyzing = true
                                DispatchQueue.global(qos: .userInitiated).async {
                                    let linuxResult = self.detectLinuxFromArchive(sourceURL: url)
                                    DispatchQueue.main.async {
                                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                            defer { self.isAnalyzing = false }

                                            if let linuxResult {
                                                self.applyLinuxDetectionResult(linuxResult, sourceURL: url, mountedImagePath: nil)
                                                return
                                            }

                                            self.log("Nie wykryto wiarygodnych sygnałów Linuxa. Kończę analizę jako nierozpoznaną.")
                                            // Użyto String(localized:) aby ten ciąg został wykryty, mimo że jest przypisywany do zmiennej
                                            self.recognizedVersion = String(localized: "Nie rozpoznano instalatora")
                                            self.requiredUSBCapacityGB = nil
                                            self.resetLinuxDetectionState()
                                            self.log("Analiza zakończona: nie rozpoznano instalatora.")
                                            AppLogging.separator()
                                        }
                                    }
                                }
                                return
                            }

                            // Użyto String(localized:) aby ten ciąg został wykryty, mimo że jest przypisywany do zmiennej
                            self.recognizedVersion = String(localized: "Nie rozpoznano instalatora")
                            self.requiredUSBCapacityGB = nil
                            self.resetLinuxDetectionState()
                            self.log("Analiza zakończona: nie rozpoznano instalatora.")
                            AppLogging.separator()
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
                            self.recognizedVersion = String(localized: "Nie rozpoznano instalatora")
                            self.requiredUSBCapacityGB = nil
                            self.resetLinuxDetectionState()
                            self.log("Analiza zakończona: nie rozpoznano instalatora.")
                            AppLogging.separator()
                        }
                    }
                }
            }
        }
    }
}
