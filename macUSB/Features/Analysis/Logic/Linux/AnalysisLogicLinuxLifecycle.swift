import Foundation
import AppKit

extension AnalysisLogic {
    private func loadLinuxDetectedSystemIcon() -> NSImage? {
        let nestedURL = Bundle.main.url(forResource: "linux", withExtension: "icns", subdirectory: "Icons/Linux")
        let rootURL = Bundle.main.url(forResource: "linux", withExtension: "icns")
        guard let url = nestedURL ?? rootURL, let icon = NSImage(contentsOf: url) else {
            return nil
        }
        icon.isTemplate = false
        return icon
    }

    func resetLinuxDetectionState() {
        self.isLinuxDetected = false
        self.isLinuxDistributionRecognized = false
        self.linuxDistro = nil
        self.linuxVersion = nil
        self.linuxEdition = nil
        self.linuxArchitecture = nil
        self.isLinuxARM = false
        self.linuxDisplayName = nil
        self.linuxSourceURL = nil
    }

    func applyLinuxDetectionResult(_ result: LinuxDetectionResult, sourceURL: URL, mountedImagePath: String?) {
        self.isLinuxDetected = result.isLinux
        self.isLinuxDistributionRecognized = result.isDistributionRecognized
        self.linuxDistro = result.distro
        self.linuxVersion = result.version
        self.linuxEdition = result.edition
        self.linuxArchitecture = result.archRaw
        self.isLinuxARM = result.isARM
        self.linuxDisplayName = result.displayName
        self.linuxSourceURL = sourceURL

        self.recognizedVersion = result.displayName
        self.sourceAppURL = nil
        self.detectedSystemIcon = loadLinuxDetectedSystemIcon()
        self.mountedDMGPath = mountedImagePath

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
        self.userSkippedAnalysis = false
        self.requiredUSBCapacityGB = nil

        self.log("Rozpoznano obraz Linux: \(result.displayName)")
        self.log("Linux source file: \(sourceURL.path)")
        self.log("Linux details: distro=\(result.distro ?? "?") version=\(result.version ?? "?") edition=\(result.edition ?? "?") arch=\(result.archRaw ?? "?") arm=\(result.isARM ? "TAK" : "NIE")")
        self.log("Linux evidence: \(result.evidence.joined(separator: ", "))")
        AppLogging.separator()
    }
}
