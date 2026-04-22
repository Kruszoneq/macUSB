import SwiftUI
import AppKit
import Foundation
import Combine

final class AnalysisLogic: ObservableObject {
    // MARK: - Published State (moved from SystemAnalysisView)
    @Published var selectedFilePath: String = ""
    @Published var selectedFileUrl: URL?
    @Published var recognizedVersion: String = ""
    @Published var sourceAppURL: URL?
    @Published var detectedSystemIcon: NSImage?
    @Published var mountedDMGPath: String? = nil

    @Published var isAnalyzing: Bool = false
    @Published var isSystemDetected: Bool = false
    @Published var showUSBSection: Bool = false
    @Published var showUnsupportedMessage: Bool = false

    // Flagi logiki systemowej
    @Published var needsCodesign: Bool = true
    @Published var isLegacyDetected: Bool = false
    @Published var isRestoreLegacy: Bool = false
    // NOWOŚĆ: Flaga dla Cataliny
    @Published var isCatalina: Bool = false
    @Published var isSierra: Bool = false
    @Published var isMavericks: Bool = false
    @Published var isUnsupportedSierra: Bool = false
    @Published var shouldShowMavericksDialog: Bool = false
    @Published var shouldShowAlreadyMountedSourceAlert: Bool = false
    @Published var isPPC: Bool = false
    @Published var legacyArchInfo: String? = nil
    @Published var userSkippedAnalysis: Bool = false
    @Published var isLinuxDetected: Bool = false
    @Published var isLinuxDistributionRecognized: Bool = false
    @Published var linuxDistro: String? = nil
    @Published var linuxVersion: String? = nil
    @Published var linuxEdition: String? = nil
    @Published var linuxArchitecture: String? = nil
    @Published var isLinuxARM: Bool = false
    @Published var linuxDisplayName: String? = nil
    @Published var linuxSourceURL: URL? = nil

    @Published var availableDrives: [USBDrive] = []
    @Published var hasUnreadableExternalUSBMedia: Bool = false
    @Published var unreadableExternalUSBMediaCount: Int = 0
    @Published var selectedDrive: USBDrive? {
        didSet {
            // Log only when the detected/selected drive actually changes
            if oldValue?.url != selectedDrive?.url {
                let id = selectedDrive?.device ?? "unknown"
                let speed = selectedDrive?.usbSpeed?.rawValue ?? "USB"
                let partitionScheme = selectedDrive?.partitionScheme?.rawValue ?? "unknown"
                let fileSystem = selectedDrive?.fileSystemFormat?.rawValue ?? "unknown"
                if isPPC {
                    self.log(
                        "Wybrano nośnik: \(id) (\(speed)) — Pojemność: \(self.selectedDrive?.size ?? "?"), Schemat: \(partitionScheme), Format: \(fileSystem), Tryb: PPC, APM",
                        category: "USBSelection"
                    )
                } else {
                    let needsFormattingText = (selectedDrive?.needsFormatting ?? true) ? "TAK" : "NIE"
                    self.log(
                        "Wybrano nośnik: \(id) (\(speed)) — Pojemność: \(self.selectedDrive?.size ?? "?"), Schemat: \(partitionScheme), Format: \(fileSystem), Wymaga formatowania w kolejnych etapach: \(needsFormattingText)",
                        category: "USBSelection"
                    )
                }
            }
        }
    }

    /// Nośnik przekazywany do etapu instalacji. W trybie PPC flaga
    /// needsFormatting jest wymuszana na false, ponieważ
    /// formatowanie (APM + HFS+) jest już wbudowane w dalszy proces.
    var selectedDriveForInstallation: USBDrive? {
        guard let drive = selectedDrive else { return nil }
        guard isPPC else { return drive }
        return USBDrive(
            name: drive.name,
            device: drive.device,
            size: drive.size,
            url: drive.url,
            usbSpeed: drive.usbSpeed,
            partitionScheme: drive.partitionScheme,
            fileSystemFormat: drive.fileSystemFormat,
            needsFormatting: false
        )
    }

    @Published var isCapacitySufficient: Bool = false
    @Published var capacityCheckFinished: Bool = false
    @Published var requiredUSBCapacityGB: Int? = nil
    var lastUnreadableUSBDetectionDate: Date = .distantPast
    let unreadableUSBDetectionInterval: TimeInterval = 2.5
    var isUnreadableUSBDetectionRunning: Bool = false

    var requiredUSBCapacityDisplayValue: String {
        requiredUSBCapacityGB.map(String.init) ?? "--"
    }

    // Computed: true only when app has recognized a supported system and can proceed normally
    var isRecognizedAndSupported: Bool {
        // Recognized and supported when analysis finished, a valid source exists or PPC flow is selected,
        // the system is detected (modern/legacy/catalina/sierra), and it's not marked unsupported.
        let recognized = (!isAnalyzing)
        let hasValidSourceOrPPC = (sourceAppURL != nil) || isPPC
        let detected = isSystemDetected || isPPC
        let unsupported = showUnsupportedMessage || isUnsupportedSierra
        return recognized && hasValidSourceOrPPC && detected && !unsupported
    }

    // MARK: - Logging
    func log(_ message: String, category: String = "FileAnalysis") {
        AppLogging.info(message, category: category)
    }

    func logError(_ message: String, category: String = "FileAnalysis") {
        AppLogging.error(message, category: category)
    }

    func stage(_ title: String) {
        AppLogging.stage(title)
    }
}
