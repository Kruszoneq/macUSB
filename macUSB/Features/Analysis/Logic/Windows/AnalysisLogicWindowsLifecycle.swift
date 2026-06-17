import Foundation
import AppKit

extension AnalysisLogic {
    private static let windowsFAT32LimitBytes: Int64 = 4_294_967_295

    var windowsFallbackSymbolName: String {
        if #available(macOS 11.0, *), NSImage(systemSymbolName: "pc", accessibilityDescription: nil) != nil {
            return "pc"
        }
        return "desktopcomputer"
    }

    private func loadWindowsDetectedSystemIcon(for family: WindowsFamily) -> NSImage? {
        let iconName: String
        switch family {
        case .eleven, .server2025:
            iconName = "Win11"
        default:
            iconName = "Win10"
        }

        let iconURL =
            Bundle.main.url(forResource: iconName, withExtension: "svg") ??
            Bundle.main.url(forResource: iconName, withExtension: "svg", subdirectory: "Icons/Windows")

        guard let iconURL,
              let icon = NSImage(contentsOf: iconURL) else {
            self.log("Nie znaleziono ikony Windows w zasobach: \(iconName).svg")
            return nil
        }

        icon.isTemplate = true
        return icon
    }

    func resetWindowsDetectionState() {
        self.isWindowsDetected = false
        self.windowsFamily = nil
        self.windowsServicePack = nil
        self.windowsArchitecture = nil
        self.isWindowsARM = false
        self.windowsHasEFI = false
        self.isWindowsWorkflowSupported = false
        self.windowsWillSplitWIM = false
        self.windowsAutounattendMacLocale = nil
    }

    func applyWindowsDetectionResult(_ result: WindowsDetectionResult, sourceURL: URL, mountedImagePath: String?) {
        InstallerSourceImageUnmountRegistry.shared.registerSourceImage(
            path: sourceURL.path,
            family: .windows,
            mountHint: mountedImagePath,
            reason: "windows_detection_result"
        )

        self.isWindowsDetected = true
        self.windowsFamily = result.family
        self.windowsServicePack = result.servicePack
        self.windowsArchitecture = result.arch
        self.isWindowsARM = result.isARM
        self.windowsHasEFI = result.efiStatus.hasEFI
        self.isWindowsWorkflowSupported = result.isSupported
        self.windowsWillSplitWIM = result.isSupported && detectWindowsWimSplitNeed(mountedImagePath: mountedImagePath)
        self.windowsAutounattendMacLocale = resolveWindowsAutounattendMacLocaleIfNeeded(
            for: result,
            mountedImagePath: mountedImagePath
        )

        self.recognizedVersion = result.displayName
        self.sourceAppURL = nil
        self.detectedSystemIcon = loadWindowsDetectedSystemIcon(for: result.family)

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

        let windowsToolchainPresence = detectWindowsToolchainPresence()
        self.log(
            "Windows toolchain presence: brew=\(windowsToolchainPresence.hasHomebrew), wimlib=\(windowsToolchainPresence.hasWimlib)"
        )
        self.log(
            "Windows toolchain paths: brew=\(windowsToolchainPresence.homebrewPath ?? "not_found"), wimlib=\(windowsToolchainPresence.wimlibPath ?? "not_found")"
        )

        if result.isSupported {
            let capacityResolution = resolveRequiredUSBCapacityForImageSource(sourceURL)
            self.requiredUSBCapacityGB = capacityResolution.requiredCapacityGB
            if let fileSizeBytes = capacityResolution.sourceFileSizeBytes,
               let fileSizeSource = capacityResolution.sourceFileSizeSource {
                self.log("Windows source size: \(fileSizeBytes) bytes (source=\(fileSizeSource))")
            } else if capacityResolution.usedFallback {
                self.log("Windows source size unavailable. Applying fallback USB threshold: \(capacityResolution.requiredCapacityGB) GB")
            }
            self.log("Windows required USB threshold: \(capacityResolution.requiredCapacityGB) GB")
        } else {
            self.requiredUSBCapacityGB = nil
        }

        if result.isSupported {
            self.isSystemDetected = true
            self.showUnsupportedMessage = false
            self.showUSBSection = false
        } else {
            self.isSystemDetected = false
            self.showUnsupportedMessage = true
            self.showUSBSection = false
        }

        self.log("Rozpoznano obraz Windows: \(result.displayName)")
        self.log("Windows support gate: supported=\(result.isSupported ? "TAK" : "NIE"), reason=\(result.supportReason.rawValue), hasEFI=\(result.efiStatus.hasEFI ? "TAK" : "NIE")")
        self.log("Windows workflow flag: isWindowsWorkflowSupported=\(self.isWindowsWorkflowSupported ? "TAK" : "NIE")")
        self.log("Windows workflow split-wim flag: \(self.windowsWillSplitWIM ? "TAK" : "NIE")")
        self.log("Windows source file: \(sourceURL.path)")
        AppLogging.separator()
    }

    private func resolveWindowsAutounattendMacLocaleIfNeeded(
        for result: WindowsDetectionResult,
        mountedImagePath: String?
    ) -> CreatorWindowsAutounattendMacLocale? {
        guard result.isSupported,
              CreatorWindowsAutounattendWindowsVersion.detected(from: result.displayName) != nil else {
            self.log("Windows autounattend language check: pominięto, bo obraz nie jest wspieranym Windows 11 dla tej funkcji.")
            return nil
        }

        let macLanguage = CreatorWindowsAutounattendMacLocale.normalizedWindowsTag(Locale.preferredLanguages.first) ?? "unknown"
        let macRegion = CreatorWindowsAutounattendMacLocale.normalizedWindowsTag(Locale.current.identifier) ?? "unknown"
        self.log(
            "Windows autounattend language check: odczytuję sources/lang.ini z obrazu Windows (mount=\(mountedImagePath ?? "nil"))."
        )

        let isoLanguageTags = CreatorWindowsAutounattendSourceInspection.availableLanguageTags(in: mountedImagePath)
        let isoLanguagesDescription = isoLanguageTags?.sorted().joined(separator: ", ") ?? "brak/nie odczytano"
        let macLocale = CreatorWindowsAutounattendMacLocale.current(availableLanguageTags: isoLanguageTags)

        self.log(
            "Windows autounattend language check: języki ISO=\(isoLanguagesDescription); język macOS=\(macLanguage); region macOS=\(macRegion); zgodność=\((macLocale?.languageIsAvailableInSource == true) ? "TAK" : "NIE")."
        )

        return macLocale
    }

    private func detectWindowsWimSplitNeed(mountedImagePath: String?) -> Bool {
        guard let mountedImagePath, !mountedImagePath.isEmpty else {
            return false
        }

        let sourcesCandidates = [
            URL(fileURLWithPath: mountedImagePath).appendingPathComponent("sources"),
            URL(fileURLWithPath: mountedImagePath).appendingPathComponent("Sources")
        ]

        for sourcesPath in sourcesCandidates where FileManager.default.fileExists(atPath: sourcesPath.path) {
            let wimCandidates = [
                sourcesPath.appendingPathComponent("install.wim"),
                sourcesPath.appendingPathComponent("INSTALL.WIM")
            ]

            for wimPath in wimCandidates {
                guard FileManager.default.fileExists(atPath: wimPath.path) else { continue }
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: wimPath.path),
                      let sizeValue = attributes[.size] as? NSNumber else {
                    continue
                }

                return sizeValue.int64Value > Self.windowsFAT32LimitBytes
            }
        }

        return false
    }
}
