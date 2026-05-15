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
    @Published var isWindowsDetected: Bool = false
    @Published var windowsFamily: WindowsFamily? = nil
    @Published var windowsServicePack: String? = nil
    @Published var windowsArchitecture: WindowsArchitecture? = nil
    @Published var isWindowsARM: Bool = false
    @Published var windowsHasEFI: Bool = false
    @Published var isWindowsWorkflowSupported: Bool = false
    @Published var windowsWillSplitWIM: Bool = false

    @Published var availableDrives: [USBDrive] = []
    @Published var hasUnreadableExternalUSBMedia: Bool = false
    @Published var unreadableExternalUSBMediaCount: Int = 0
    @Published var selectedDriveSelectionID: String? {
        didSet {
            guard !isSynchronizingDriveSelection else { return }

            let normalizedSelectionID: String?
            if let selectedDriveSelectionID, selectedDriveSelectionID.isEmpty {
                normalizedSelectionID = nil
            } else {
                normalizedSelectionID = selectedDriveSelectionID
            }

            if normalizedSelectionID != selectedDriveSelectionID {
                synchronizeDriveSelection {
                    self.selectedDriveSelectionID = normalizedSelectionID
                }
                return
            }

            guard let selectionID = normalizedSelectionID else {
                if selectedDrive != nil {
                    selectedDrive = nil
                }
                return
            }

            if let matchingDrive = availableDrives.first(where: { $0.selectionID == selectionID }) {
                if selectedDrive?.selectionID != matchingDrive.selectionID {
                    selectedDrive = matchingDrive
                }
            } else if selectedDrive != nil {
                selectedDrive = nil
            }
        }
    }

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

            let newSelectionID = selectedDrive?.selectionID
            if selectedDriveSelectionID != newSelectionID {
                synchronizeDriveSelection {
                    self.selectedDriveSelectionID = newSelectionID
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
    var isLinuxPhysicalDriveRefreshRunning: Bool = false
    var linuxWholeDiskCapacityCache: [String: Int64] = [:]
    let imageAnalysisTimeoutSeconds: TimeInterval = 20
    var activeImageAnalysisRunID: UUID? = nil
    var imageAnalysisTimeoutWorkItem: DispatchWorkItem? = nil
    var linuxImageAttachSession: LinuxImageAttachSession? = nil
    private var isSynchronizingDriveSelection: Bool = false

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

    func synchronizeDriveSelection(_ updates: () -> Void) {
        if isSynchronizingDriveSelection {
            updates()
            return
        }

        isSynchronizingDriveSelection = true
        updates()
        isSynchronizingDriveSelection = false
    }
}

extension AnalysisLogic {
    func beginImageAnalysisRun(sourceURL: URL) -> UUID {
        cancelActiveImageAnalysisRun(reason: "Uruchamianie nowej analizy obrazu")

        let runID = UUID()
        activeImageAnalysisRunID = runID

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.handleImageAnalysisTimeout(runID: runID, sourceURL: sourceURL)
        }
        imageAnalysisTimeoutWorkItem = timeoutWorkItem

        log("Uruchomiono timeout analizy obrazu: \(Int(imageAnalysisTimeoutSeconds)) s [runID=\(runID.uuidString)]")
        DispatchQueue.main.asyncAfter(deadline: .now() + imageAnalysisTimeoutSeconds, execute: timeoutWorkItem)
        return runID
    }

    @discardableResult
    func completeImageAnalysisRunIfCurrent(_ runID: UUID, reason: String) -> Bool {
        guard activeImageAnalysisRunID == runID else { return false }
        imageAnalysisTimeoutWorkItem?.cancel()
        imageAnalysisTimeoutWorkItem = nil
        activeImageAnalysisRunID = nil
        log("Zakończono analizę obrazu przed timeoutem [runID=\(runID.uuidString)]: \(reason)")
        return true
    }

    func isImageAnalysisRunCurrent(_ runID: UUID) -> Bool {
        activeImageAnalysisRunID == runID
    }

    func cancelActiveImageAnalysisRun(reason: String) {
        guard let runID = activeImageAnalysisRunID else {
            imageAnalysisTimeoutWorkItem?.cancel()
            imageAnalysisTimeoutWorkItem = nil
            cleanupLinuxAttachSession(reason: "cancel_active_run_no_id")
            return
        }

        imageAnalysisTimeoutWorkItem?.cancel()
        imageAnalysisTimeoutWorkItem = nil
        activeImageAnalysisRunID = nil
        log("Anulowano aktywną sesję analizy obrazu [runID=\(runID.uuidString)]: \(reason)")
        cleanupLinuxAttachSession(reason: "cancel_active_run")
    }

    func logIgnoredStaleImageAnalysisCallback(_ runID: UUID, stage: String) {
        log("Ignoruję spóźniony wynik analizy obrazu [runID=\(runID.uuidString)] (\(stage)).")
    }

    func applyUnrecognizedInstallerState(timeoutReason: String? = nil) {
        if let timeoutReason {
            logError(timeoutReason)
        }
        recognizedVersion = String(localized: "Nie rozpoznano instalatora")
        requiredUSBCapacityGB = nil
        sourceAppURL = nil
        detectedSystemIcon = nil
        isSystemDetected = false
        showUSBSection = false
        showUnsupportedMessage = false
        resetLinuxDetectionState()
        resetWindowsDetectionState()
        isAnalyzing = false
        log("Analiza zakończona: nie rozpoznano instalatora.")
        AppLogging.separator()
    }

    private func handleImageAnalysisTimeout(runID: UUID, sourceURL: URL) {
        guard activeImageAnalysisRunID == runID else { return }

        imageAnalysisTimeoutWorkItem = nil
        activeImageAnalysisRunID = nil

        let ext = sourceURL.pathExtension.lowercased()
        if ext == "iso" {
            captureLinuxAttachSessionIfNeeded(sourceURL: sourceURL, reason: "timeout_pre_cleanup")
        }
        cleanupLinuxAttachSession(reason: "image_analysis_timeout")
        detachMountedImageAfterAnalysisTimeout(sourceURL: sourceURL)

        applyUnrecognizedInstallerState(
            timeoutReason: "Przekroczono timeout analizy obrazu (\(Int(imageAnalysisTimeoutSeconds)) s): \(sourceURL.lastPathComponent). Anuluję analizowanie i oznaczam obraz jako niewspierany/nierozpoznany."
        )
    }

    private func detachMountedImageAfterAnalysisTimeout(sourceURL: URL) {
        var mountPaths: [String] = []

        if let mountedDMGPath, !mountedDMGPath.isEmpty {
            mountPaths.append(mountedDMGPath)
        }

        if let discoveredPath = mountedPathForAttachedSourceImage(sourceURL: sourceURL), !discoveredPath.isEmpty {
            mountPaths.append(discoveredPath)
        }

        let uniqueMountPaths = Array(Set(mountPaths)).sorted()
        guard !uniqueMountPaths.isEmpty else {
            log("Timeout analizy obrazu: brak aktywnego mount-point do odmontowania dla \(sourceURL.lastPathComponent).")
            return
        }

        for mountPath in uniqueMountPaths {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            task.arguments = ["detach", mountPath, "-force"]
            let errorPipe = Pipe()
            task.standardError = errorPipe

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                logError("Timeout analizy obrazu: nie udało się uruchomić odmontowania \(mountPath): \(error.localizedDescription)")
                continue
            }

            if task.terminationStatus == 0 {
                log("Timeout analizy obrazu: odmontowano obraz \(mountPath).")
            } else {
                let stderrText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if stderrText.isEmpty {
                    logError("Timeout analizy obrazu: odmontowanie nie powiodło się dla \(mountPath) (kod \(task.terminationStatus)).")
                } else {
                    logError("Timeout analizy obrazu: odmontowanie nie powiodło się dla \(mountPath): \(stderrText)")
                }
            }
        }

        if let currentMountedPath = mountedDMGPath,
           uniqueMountPaths.contains(currentMountedPath) {
            mountedDMGPath = nil
        }
    }

    private func mountedPathForAttachedSourceImage(sourceURL: URL) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["info", "-plist"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            logError("Timeout analizy obrazu: nie udało się uruchomić hdiutil info: \(error.localizedDescription)")
            return nil
        }
        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0 else {
            let stderrText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                logError("Timeout analizy obrazu: hdiutil info zakończył się błędem (kod \(task.terminationStatus)).")
            } else {
                logError("Timeout analizy obrazu: hdiutil info zakończył się błędem: \(stderrText)")
            }
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: outputData, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return nil
        }

        let sourcePath = URL(fileURLWithPath: sourceURL.path).resolvingSymlinksInPath().standardizedFileURL.path
        for image in images {
            guard let imagePath = image["image-path"] as? String else { continue }
            let normalizedImagePath = URL(fileURLWithPath: imagePath).resolvingSymlinksInPath().standardizedFileURL.path
            guard normalizedImagePath == sourcePath else { continue }
            guard let entities = image["system-entities"] as? [[String: Any]],
                  let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
                continue
            }
            return mountPoint
        }

        return nil
    }
}
