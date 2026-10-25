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
    @Published var isBetaInstaller: Bool = false
    @Published var mountedDMGPath: String? = nil

    @Published var isAnalyzing: Bool = false {
        didSet {
            updateAnalysisOperationActivity(from: oldValue)
        }
    }
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
    @Published var createInstallMediaInspection: MacOSCreateInstallMediaInspection = .notApplicable
    @Published var macOSArchitectureBlockReason: MacOSArchitectureBlockReason? = nil
    @Published var macOSRosettaRequirement: MacOSRosettaRequirement = .notRequired
    @Published var userSkippedAnalysis: Bool = false
    @Published var isLinuxDetected: Bool = false
    @Published var isRawImageSelection: Bool = false
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
    @Published var windowsBootCapabilities: WindowsBootCapabilities? = nil
    @Published var isWindowsWorkflowSupported: Bool = false
    @Published var windowsWillSplitWIM: Bool = false
    @Published var windowsAutounattendMacLocale: CreatorWindowsAutounattendMacLocale? = nil

    @Published var presentedUSBTargets: [USBDrive] = []
    @Published var selectedDriveSelectionID: String? {
        didSet {
            guard !isSynchronizingDriveSelection else { return }

            resolveUSBSelection(selectedDriveSelectionID)
        }
    }

    @Published var selectedDrive: USBDrive? {
        didSet {
            // Log only when the detected/selected drive actually changes
            if oldValue?.url != selectedDrive?.url {
                let id = selectedDrive?.device ?? "unknown"
                let speed = selectedDrive?.mediaDisplayName ?? "USB"
                let partitionScheme = selectedDrive?.partitionScheme?.rawValue ?? "unknown"
                let fileSystem = selectedDrive?.fileSystemFormat?.rawValue ?? "unknown"
                if isPPC {
                    self.log(
                        "Selected target: \(id) (\(speed)) — Capacity: \(self.selectedDrive?.size ?? "?"), Partition scheme: \(partitionScheme), Format: \(fileSystem), Mode: PPC, APM",
                        category: "USBSelection"
                    )
                } else {
                    let needsFormattingText = (selectedDrive?.needsFormatting ?? true) ? "yes" : "no"
                    self.log(
                        "Selected target: \(id) (\(speed)) — Capacity: \(self.selectedDrive?.size ?? "?"), Partition scheme: \(partitionScheme), Format: \(fileSystem), Requires formatting in later stages: \(needsFormattingText)",
                        category: "USBSelection"
                    )
                }
            }

            if !isSynchronizingDriveSelection {
                selectedTargetIdentity = selectedDrive.flatMap { usbDiscoveryState.snapshot?.verification[$0.selectionID]?.identity }
                checkCapacity(logResult: true)
            }

            let newSelectionID = selectedDrive?.selectionID
            if selectedDriveSelectionID != newSelectionID {
                synchronizeDriveSelection {
                    self.selectedDriveSelectionID = newSelectionID
                }
            }
        }
    }

    /// Nośnik przekazywany do etapu instalacji. Tylko PPC
    /// zawsze otrzymuje fizyczny whole disk. W trybie PPC flaga
    /// needsFormatting jest wymuszana na false, ponieważ formatowanie
    /// (APM + HFS+) jest już wbudowane w dalszy proces.
    var selectedDriveForInstallation: USBDrive? {
        guard usbTargetReadiness.isReady, usbDiscoveryState.hasCurrentSnapshot,
              usbDiscoveryState.snapshot?.allowExternalDrives == UserDefaults.standard.bool(forKey: "AllowExternalDrives"),
              let drive = selectedDrive,
              let proof = usbDiscoveryState.snapshot?.verification[drive.selectionID], proof.problem == nil, proof.isFresh(),
              proof.identity == selectedTargetIdentity,
              case .success(let bytes) = proof.capacity,
              let required = usbTargetCapacityRequirement?.minimumBytes, bytes >= required else { return nil }
        let installationDrive: USBDrive
        if requiresWholeDiskMacOSTarget {
            if drive.isWholeDiskTarget {
                installationDrive = drive
            } else {
                let wholeDisk = USBDriveLogic.wholeDiskName(from: drive.device)
                guard let physicalDrive = physicalUSBTargetsCache.first(where: { $0.device == wholeDisk }) else {
                    return nil
                }
                installationDrive = physicalDrive
            }
        } else {
            installationDrive = drive
        }

        guard isPPC else { return installationDrive }
        return USBDrive(
            name: installationDrive.name,
            device: installationDrive.device,
            size: installationDrive.size,
            url: installationDrive.url,
            usbSpeed: installationDrive.usbSpeed,
            mediaKind: installationDrive.mediaKind,
            partitionScheme: installationDrive.partitionScheme,
            fileSystemFormat: installationDrive.fileSystemFormat,
            needsFormatting: false
        )
    }

    @Published var usbDiscoveryState = AnalysisUSBDiscoveryState()
    @Published var heldUSBDiscoveryPresentation: AnalysisUSBHeldPresentation?
    @Published var usbTargetReadiness: USBTargetReadiness = .noSelection
    @Published var usbTargetCapacityRequirement: USBTargetCapacityRequirement? = nil
    @Published var shouldShowSourceSizeUnavailableAlert: Bool = false
    var driveRefreshPolicy = USBDriveRefreshPolicy()
    var isDriveRefreshVisible = false
    var driveRefreshCancellation: USBDiscoveryCancellation?
    var physicalDriveRefreshGeneration: UInt = 0
    var selectedTargetIdentity: String?
    var isUSBSelectionAlertPresented = false
    let usbDiscoveryDiagnostics = USBDiscoveryDiagnostics()
    var isMacOSCreateInstallMediaVolumeOverrideActive: Bool = false

    var physicalUSBTargetsCache: [USBDrive] { usbDiscoveryState.snapshot?.physicalDrives ?? [] }
    var macOSOptionUSBTargetsCache: [USBDrive] { usbDiscoveryState.snapshot?.optionDrives ?? [] }
    var hasPreparedUSBTargetSnapshot: Bool { usbDiscoveryState.snapshot != nil }
    var isCapacitySufficient: Bool { usbTargetReadiness.isReady }
    var capacityCheckFinished: Bool {
        switch usbTargetReadiness {
        case .ready, .insufficient: return true
        default: return false
        }
    }

    deinit {
        driveRefreshCancellation?.cancel()
    }
    let imageAnalysisTimeoutSeconds: TimeInterval = 20
    var activeImageAnalysisRunID: UUID? = nil
    var imageAnalysisTimeoutWorkItem: DispatchWorkItem? = nil
    var linuxImageAttachSession: LinuxImageAttachSession? = nil
    var analysisOperationToken: AppActiveOperationToken?
    private var isSynchronizingDriveSelection: Bool = false

    var requiredUSBCapacityDisplayValue: String {
        usbTargetCapacityRequirement.map { String($0.displayCapacityGB) } ?? "--"
    }

    var requiredVolumeCapacityDisplayValue: String {
        guard let minimumBytes = usbTargetCapacityRequirement?.minimumBytes else { return "--" }
        let tenths = minimumBytes / 100_000_000 + (minimumBytes % 100_000_000 == 0 ? 0 : 1)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: Double(tenths) / 10)) ?? "--"
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
    var selectedWorkflowForLogging: AppLogging.Workflow? {
        if isRawImageSelection { return .raw }
        if isWindowsDetected { return .windows }
        if isLinuxDetected { return .linux }
        if isPPC { return .ppc }
        if isSystemDetected { return .macos }
        return nil
    }

    func log(_ message: String, category: String = "FileAnalysis", workflow: AppLogging.Workflow? = nil) {
        let stage: AppLogging.Stage = category == "USBSelection" ? .usb : .analysis
        AppLogging.info(message, stage: stage, workflow: workflow ?? (stage == .usb ? selectedWorkflowForLogging : nil))
    }

    func logError(_ message: String, category: String = "FileAnalysis", workflow: AppLogging.Workflow? = nil) {
        let stage: AppLogging.Stage = category == "USBSelection" ? .usb : .analysis
        AppLogging.error(message, stage: stage, workflow: workflow ?? (stage == .usb ? selectedWorkflowForLogging : nil))
    }

    func logUnclassified(_ message: String) {
        AppLogging.info(message, stage: .analysis)
    }

    func logUnclassifiedError(_ message: String) {
        AppLogging.error(message, stage: .analysis)
    }

    func logMacOS(_ message: String, category: String = "FileAnalysis") {
        log(message, category: category, workflow: .macos)
    }

    func logMacOSError(_ message: String, category: String = "FileAnalysis") {
        logError(message, category: category, workflow: .macos)
    }

    func logDetectedMacOS(_ message: String) {
        log(message, workflow: isPPC ? .ppc : .macos)
    }

    func logDetectedMacOSError(_ message: String) {
        logError(message, workflow: isPPC ? .ppc : .macos)
    }

    func logWindows(_ message: String, category: String = "FileAnalysis") {
        log(message, category: category, workflow: .windows)
    }

    func logWindowsError(_ message: String, category: String = "FileAnalysis") {
        logError(message, category: category, workflow: .windows)
    }

    func logLinux(_ message: String, category: String = "FileAnalysis") {
        log(message, category: category, workflow: .linux)
    }

    func logLinuxError(_ message: String, category: String = "FileAnalysis") {
        logError(message, category: category, workflow: .linux)
    }

    func logRaw(_ message: String, category: String = "FileAnalysis") {
        log(message, category: category, workflow: .raw)
    }

    func logRawError(_ message: String, category: String = "FileAnalysis") {
        logError(message, category: category, workflow: .raw)
    }

    func stage(_ title: String, workflow: AppLogging.Workflow? = nil) {
        AppLogging.info(title, stage: .analysis, workflow: workflow)
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
        cancelActiveImageAnalysisRun(reason: "starting a new image analysis")

        let runID = UUID()
        activeImageAnalysisRunID = runID

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.handleImageAnalysisTimeout(runID: runID, sourceURL: sourceURL)
        }
        imageAnalysisTimeoutWorkItem = timeoutWorkItem

        log("Image analysis timeout started: \(Int(imageAnalysisTimeoutSeconds)) s [runID=\(runID.uuidString)]")
        DispatchQueue.main.asyncAfter(deadline: .now() + imageAnalysisTimeoutSeconds, execute: timeoutWorkItem)
        return runID
    }

    @discardableResult
    func completeImageAnalysisRunIfCurrent(_ runID: UUID, reason: String) -> Bool {
        guard activeImageAnalysisRunID == runID else { return false }
        imageAnalysisTimeoutWorkItem?.cancel()
        imageAnalysisTimeoutWorkItem = nil
        activeImageAnalysisRunID = nil
        log("Image analysis completed before timeout [runID=\(runID.uuidString)]: \(reason)", workflow: selectedWorkflowForLogging)
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
        log("Active image analysis session cancelled [runID=\(runID.uuidString)]: \(reason)")
        cleanupLinuxAttachSession(reason: "cancel_active_run")
    }

    func logIgnoredStaleImageAnalysisCallback(_ runID: UUID, stage: String) {
        log("Ignoring stale image analysis result [runID=\(runID.uuidString)] (\(stage)).")
    }

    func applyUnrecognizedInstallerState(timeoutReason: String? = nil) {
        if let timeoutReason {
            logError(timeoutReason)
        }
        recognizedVersion = String(localized: "analysis.result.unrecognized.description", table: "Analysis")
        usbTargetCapacityRequirement = nil
        shouldShowSourceSizeUnavailableAlert = false
        sourceAppURL = nil
        detectedSystemIcon = nil
        isBetaInstaller = false
        isSystemDetected = false
        showUSBSection = false
        showUnsupportedMessage = false
        resetLinuxDetectionState()
        resetWindowsDetectionState()
        isAnalyzing = false
        log("Analysis completed: installer not recognized.")
        AppLogging.separator(stage: .analysis)
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
            timeoutReason: "Image analysis timed out (\(Int(imageAnalysisTimeoutSeconds)) s): \(sourceURL.lastPathComponent). Cancelling analysis and marking the image unsupported or unrecognized."
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
            log("Image analysis timeout: no active mount point to detach for \(sourceURL.lastPathComponent).")
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
                logError("Image analysis timeout: failed to start detaching \(mountPath): \(error.localizedDescription)")
                continue
            }

            if task.terminationStatus == 0 {
                log("Image analysis timeout: detached image \(mountPath).")
            } else {
                let stderrText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if stderrText.isEmpty {
                    logError("Image analysis timeout: detaching failed for \(mountPath) (exit code \(task.terminationStatus)).")
                } else {
                    logError("Image analysis timeout: detaching failed for \(mountPath): \(stderrText)")
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
            logError("Image analysis timeout: failed to start hdiutil info: \(error.localizedDescription)")
            return nil
        }
        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0 else {
            let stderrText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                logError("Image analysis timeout: hdiutil info failed (exit code \(task.terminationStatus)).")
            } else {
                logError("Image analysis timeout: hdiutil info failed: \(stderrText)")
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
