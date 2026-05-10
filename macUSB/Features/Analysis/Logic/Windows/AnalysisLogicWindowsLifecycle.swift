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
    }

    func applyWindowsDetectionResult(_ result: WindowsDetectionResult, sourceURL: URL, mountedImagePath: String?) {
        self.isWindowsDetected = true
        self.windowsFamily = result.family
        self.windowsServicePack = result.servicePack
        self.windowsArchitecture = result.arch
        self.isWindowsARM = result.isARM
        self.windowsHasEFI = result.efiStatus.hasEFI
        self.isWindowsWorkflowSupported = result.isSupported
        self.windowsWillSplitWIM = result.isSupported && detectWindowsWimSplitNeed(mountedImagePath: mountedImagePath)

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
        self.requiredUSBCapacityGB = result.isSupported ? 8 : nil

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
