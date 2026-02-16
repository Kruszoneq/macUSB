import Foundation
import Darwin

enum HelperWorkflowKind: String, Codable {
    case standard
    case legacyRestore
    case mavericks
    case ppc
}

struct HelperWorkflowRequestPayload: Codable {
    let workflowKind: HelperWorkflowKind
    let systemName: String
    let sourceAppPath: String
    let originalImagePath: String?
    let tempWorkPath: String
    let targetVolumePath: String
    let targetBSDName: String
    let targetLabel: String
    let needsPreformat: Bool
    let isCatalina: Bool
    let isSierra: Bool
    let needsCodesign: Bool
    let requiresApplicationPathArg: Bool
    let requesterUID: Int?
}

struct HelperProgressEventPayload: Codable {
    let workflowID: String
    let stageKey: String
    let stageTitleKey: String
    let percent: Double
    let statusKey: String
    let logLine: String?
    let timestamp: Date
}

struct HelperWorkflowResultPayload: Codable {
    let workflowID: String
    let success: Bool
    let failedStage: String?
    let errorCode: Int?
    let errorMessage: String?
    let isUserCancelled: Bool
}

@objc(MacUSBPrivilegedHelperToolXPCProtocol)
protocol PrivilegedHelperToolXPCProtocol {
    func startWorkflow(_ requestData: NSData, reply: @escaping (NSString?, NSError?) -> Void)
    func cancelWorkflow(_ workflowID: String, reply: @escaping (Bool, NSError?) -> Void)
    func queryHealth(_ reply: @escaping (Bool, NSString) -> Void)
}

@objc(MacUSBPrivilegedHelperClientXPCProtocol)
protocol PrivilegedHelperClientXPCProtocol {
    func receiveProgressEvent(_ eventData: NSData)
    func finishWorkflow(_ resultData: NSData)
}

enum HelperXPCCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

private enum HelperExecutionError: Error {
    case cancelled
    case failed(stage: String, exitCode: Int32, description: String)
    case invalidRequest(String)
}

private struct WorkflowStage {
    let key: String
    let titleKey: String
    let statusKey: String
    let startPercent: Double
    let endPercent: Double
    let executable: String
    let arguments: [String]
    let parseToolPercent: Bool
}

private struct PreparedWorkflowContext {
    let sourcePath: String
    let postInstallSourceAppPath: String?
}

private final class HelperWorkflowExecutor {
    private let request: HelperWorkflowRequestPayload
    private let workflowID: String
    private let sendEvent: (HelperProgressEventPayload) -> Void

    private let fileManager = FileManager.default
    private var isCancelled = false
    private let stateQueue = DispatchQueue(label: "macUSB.helper.executor.state")
    private var activeProcess: Process?
    private var latestPercent: Double = 0
    private var lastStageOutputLine: String?

    init(request: HelperWorkflowRequestPayload, workflowID: String, sendEvent: @escaping (HelperProgressEventPayload) -> Void) {
        self.request = request
        self.workflowID = workflowID
        self.sendEvent = sendEvent
    }

    func cancel() {
        stateQueue.sync {
            isCancelled = true
            guard let process = activeProcess, process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    func run() -> HelperWorkflowResultPayload {
        do {
            let context = try prepareWorkflowContext()
            let stages = try buildStages(using: context)
            for stage in stages {
                try throwIfCancelled()
                if stage.key == "catalina_copy" {
                    let transitionMessage = "Catalina: zakończono createinstallmedia, przejście do etapu ditto."
                    emit(stage: stage, percent: stage.startPercent, statusKey: stage.statusKey, logLine: transitionMessage)
                } else {
                    emit(stage: stage, percent: stage.startPercent, statusKey: stage.statusKey)
                }
                try runStage(stage)
                emit(stage: stage, percent: stage.endPercent, statusKey: stage.statusKey)
            }

            runBestEffortTempCleanupStage()
            runFinalizeStage()

            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: true,
                failedStage: nil,
                errorCode: nil,
                errorMessage: nil,
                isUserCancelled: false
            )
        } catch HelperExecutionError.cancelled {
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "cancelled",
                errorCode: nil,
                errorMessage: "Operacja została anulowana przez użytkownika.",
                isUserCancelled: true
            )
        } catch HelperExecutionError.failed(let stage, let exitCode, let description) {
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: stage,
                errorCode: Int(exitCode),
                errorMessage: description,
                isUserCancelled: false
            )
        } catch HelperExecutionError.invalidRequest(let message) {
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "request",
                errorCode: nil,
                errorMessage: message,
                isUserCancelled: false
            )
        } catch {
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "unknown",
                errorCode: nil,
                errorMessage: error.localizedDescription,
                isUserCancelled: false
            )
        }
    }

    private func prepareWorkflowContext() throws -> PreparedWorkflowContext {
        let stageKey = "prepare_source"
        let stageTitleKey = HelperWorkflowLocalizationKeys.prepareSourceTitle
        let statusKey = HelperWorkflowLocalizationKeys.prepareSourceStatus

        emitProgress(
            stageKey: stageKey,
            titleKey: stageTitleKey,
            percent: 0,
            statusKey: statusKey
        )

        try ensureTempWorkDirectoryExists()

        let context: PreparedWorkflowContext
        switch request.workflowKind {
        case .legacyRestore:
            let sourceESD = URL(fileURLWithPath: request.sourceAppPath)
                .appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")
            guard fileManager.fileExists(atPath: sourceESD.path) else {
                throw HelperExecutionError.invalidRequest("Nie znaleziono pliku InstallESD.dmg.")
            }

            let stagedESD = URL(fileURLWithPath: request.tempWorkPath).appendingPathComponent("InstallESD.dmg")
            try copyReplacingItem(at: sourceESD, to: stagedESD)
            context = PreparedWorkflowContext(sourcePath: stagedESD.path, postInstallSourceAppPath: nil)

        case .mavericks:
            let sourceImagePath = request.originalImagePath ?? request.sourceAppPath
            guard fileManager.fileExists(atPath: sourceImagePath) else {
                throw HelperExecutionError.invalidRequest("Nie znaleziono źródłowego pliku obrazu.")
            }

            let sourceImage = URL(fileURLWithPath: sourceImagePath)
            let stagedImage = URL(fileURLWithPath: request.tempWorkPath).appendingPathComponent("InstallESD.dmg")
            try copyReplacingItem(at: sourceImage, to: stagedImage)
            context = PreparedWorkflowContext(sourcePath: stagedImage.path, postInstallSourceAppPath: nil)

        case .ppc:
            let mountedVolumeSource = URL(fileURLWithPath: request.sourceAppPath)
                .deletingLastPathComponent()
                .path
            let mountedSourceAvailable = mountedVolumeSource.hasPrefix("/Volumes/") &&
                fileManager.fileExists(atPath: mountedVolumeSource)

            if let imagePath = request.originalImagePath, fileManager.fileExists(atPath: imagePath) {
                let imageURL = URL(fileURLWithPath: imagePath)
                let sourceExt = imageURL.pathExtension.lowercased()

                if (sourceExt == "iso" || sourceExt == "cdr"), mountedSourceAvailable {
                    let message = "PPC helper strategy: asr restore from mounted source (ISO/CDR) -> /Volumes/PPC"
                    emitProgress(
                        stageKey: stageKey,
                        titleKey: stageTitleKey,
                        percent: latestPercent,
                        statusKey: statusKey,
                        logLine: message,
                        shouldAdvancePercent: false
                    )
                    context = PreparedWorkflowContext(sourcePath: mountedVolumeSource, postInstallSourceAppPath: nil)
                } else {
                    let stagedImageURL = URL(fileURLWithPath: request.tempWorkPath)
                        .appendingPathComponent("PPC_\(imageURL.lastPathComponent)")
                    try copyReplacingItem(at: imageURL, to: stagedImageURL)
                    let message = "PPC helper strategy: asr restore from staged image -> /Volumes/PPC"
                    emitProgress(
                        stageKey: stageKey,
                        titleKey: stageTitleKey,
                        percent: latestPercent,
                        statusKey: statusKey,
                        logLine: message,
                        shouldAdvancePercent: false
                    )
                    context = PreparedWorkflowContext(sourcePath: stagedImageURL.path, postInstallSourceAppPath: nil)
                }
            } else if mountedSourceAvailable {
                let message = "PPC helper strategy: asr restore from mounted source fallback -> /Volumes/PPC"
                emitProgress(
                    stageKey: stageKey,
                    titleKey: stageTitleKey,
                    percent: latestPercent,
                    statusKey: statusKey,
                    logLine: message,
                    shouldAdvancePercent: false
                )
                context = PreparedWorkflowContext(sourcePath: mountedVolumeSource, postInstallSourceAppPath: nil)
            } else {
                throw HelperExecutionError.invalidRequest("Nie znaleziono źródła PPC do przywracania.")
            }

        case .standard:
            let sourceAppURL = URL(fileURLWithPath: request.sourceAppPath)
            var effectiveAppURL = sourceAppURL
            let sourceIsMountedVolume = request.sourceAppPath.hasPrefix("/Volumes/")

            if request.isSierra {
                let destinationAppURL = URL(fileURLWithPath: request.tempWorkPath)
                    .appendingPathComponent(sourceAppURL.lastPathComponent)
                try copyReplacingItem(at: sourceAppURL, to: destinationAppURL)

                try runSimpleCommand(
                    executable: "/usr/bin/plutil",
                    arguments: ["-replace", "CFBundleShortVersionString", "-string", "12.6.03", destinationAppURL.appendingPathComponent("Contents/Info.plist").path],
                    stageKey: stageKey,
                    stageTitleKey: stageTitleKey,
                    statusKey: statusKey
                )
                try runSimpleCommand(
                    executable: "/usr/bin/xattr",
                    arguments: ["-dr", "com.apple.quarantine", destinationAppURL.path],
                    stageKey: stageKey,
                    stageTitleKey: stageTitleKey,
                    statusKey: statusKey
                )
                try runSimpleCommand(
                    executable: "/usr/bin/codesign",
                    arguments: ["-s", "-", "-f", destinationAppURL.appendingPathComponent("Contents/Resources/createinstallmedia").path],
                    stageKey: stageKey,
                    stageTitleKey: stageTitleKey,
                    statusKey: statusKey
                )

                effectiveAppURL = destinationAppURL
            } else if sourceIsMountedVolume || request.isCatalina || request.needsCodesign {
                let destinationAppURL = URL(fileURLWithPath: request.tempWorkPath)
                    .appendingPathComponent(sourceAppURL.lastPathComponent)
                try copyReplacingItem(at: sourceAppURL, to: destinationAppURL)

                if request.isCatalina || request.needsCodesign {
                    try performLocalCodesign(
                        on: destinationAppURL,
                        stageKey: stageKey,
                        stageTitleKey: stageTitleKey,
                        statusKey: statusKey
                    )
                }

                effectiveAppURL = destinationAppURL
            }

            let postInstallSourcePath = request.isCatalina
                ? URL(fileURLWithPath: request.sourceAppPath).resolvingSymlinksInPath().path
                : nil

            context = PreparedWorkflowContext(
                sourcePath: effectiveAppURL.path,
                postInstallSourceAppPath: postInstallSourcePath
            )
        }

        emitProgress(
            stageKey: stageKey,
            titleKey: stageTitleKey,
            percent: 10,
            statusKey: statusKey
        )

        return context
    }

    private func buildStages(using context: PreparedWorkflowContext) throws -> [WorkflowStage] {
        let wholeDisk = try extractWholeDiskName(from: request.targetBSDName)
        let rawTargetPath = request.targetVolumePath
        var effectiveTargetPath = rawTargetPath

        var stages: [WorkflowStage] = []

        if request.workflowKind != .ppc && request.needsPreformat {
            stages.append(
                WorkflowStage(
                    key: "preformat",
                    titleKey: HelperWorkflowLocalizationKeys.preformatTitle,
                    statusKey: HelperWorkflowLocalizationKeys.preformatStatus,
                    startPercent: 10,
                    endPercent: 30,
                    executable: "/usr/sbin/diskutil",
                    arguments: ["partitionDisk", "/dev/\(wholeDisk)", "GPT", "HFS+", request.targetLabel, "100%"],
                    parseToolPercent: false
                )
            )
            effectiveTargetPath = "/Volumes/\(request.targetLabel)"
        }

        switch request.workflowKind {
        case .legacyRestore:
            stages.append(
                WorkflowStage(
                    key: "imagescan",
                    titleKey: HelperWorkflowLocalizationKeys.imagescanTitle,
                    statusKey: HelperWorkflowLocalizationKeys.imagescanStatus,
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.needsPreformat ? 50 : 35,
                    executable: "/usr/sbin/asr",
                    arguments: ["imagescan", "--source", context.sourcePath],
                    parseToolPercent: true
                )
            )
            stages.append(
                WorkflowStage(
                    key: "restore",
                    titleKey: HelperWorkflowLocalizationKeys.restoreTitle,
                    statusKey: HelperWorkflowLocalizationKeys.restoreStatus,
                    startPercent: request.needsPreformat ? 50 : 35,
                    endPercent: 98,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", context.sourcePath, "--target", effectiveTargetPath, "--erase", "--noprompt", "--noverify"],
                    parseToolPercent: true
                )
            )

        case .mavericks:
            stages.append(
                WorkflowStage(
                    key: "imagescan",
                    titleKey: HelperWorkflowLocalizationKeys.imagescanTitle,
                    statusKey: HelperWorkflowLocalizationKeys.imagescanStatus,
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.needsPreformat ? 50 : 35,
                    executable: "/usr/sbin/asr",
                    arguments: ["imagescan", "--source", context.sourcePath],
                    parseToolPercent: true
                )
            )
            stages.append(
                WorkflowStage(
                    key: "restore",
                    titleKey: HelperWorkflowLocalizationKeys.restoreTitle,
                    statusKey: HelperWorkflowLocalizationKeys.restoreStatus,
                    startPercent: request.needsPreformat ? 50 : 35,
                    endPercent: 98,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", context.sourcePath, "--target", effectiveTargetPath, "--erase", "--noprompt", "--noverify"],
                    parseToolPercent: true
                )
            )

        case .ppc:
            stages.append(
                WorkflowStage(
                    key: "ppc_format",
                    titleKey: HelperWorkflowLocalizationKeys.ppcFormatTitle,
                    statusKey: HelperWorkflowLocalizationKeys.ppcFormatStatus,
                    startPercent: 10,
                    endPercent: 25,
                    executable: "/usr/sbin/diskutil",
                    arguments: ["partitionDisk", "/dev/\(wholeDisk)", "APM", "HFS+", "PPC", "100%"],
                    parseToolPercent: false
                )
            )

            let ppcRestoreSource = resolvePPCSourceArgument(from: context.sourcePath)
            stages.append(
                WorkflowStage(
                    key: "ppc_restore",
                    titleKey: HelperWorkflowLocalizationKeys.ppcRestoreTitle,
                    statusKey: HelperWorkflowLocalizationKeys.ppcRestoreStatus,
                    startPercent: 25,
                    endPercent: 98,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", ppcRestoreSource, "--target", "/Volumes/PPC", "--erase", "--noverify", "--noprompt", "--verbose"],
                    parseToolPercent: false
                )
            )

        case .standard:
            let createinstallmediaPath = (context.sourcePath as NSString).appendingPathComponent("Contents/Resources/createinstallmedia")
            var createArgs: [String] = ["--volume", effectiveTargetPath]
            if request.requiresApplicationPathArg {
                createArgs.append(contentsOf: ["--applicationpath", context.sourcePath])
            }
            createArgs.append("--nointeraction")

            stages.append(
                WorkflowStage(
                    key: "createinstallmedia",
                    titleKey: HelperWorkflowLocalizationKeys.createinstallmediaTitle,
                    statusKey: HelperWorkflowLocalizationKeys.createinstallmediaStatus,
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.isCatalina ? 90 : 98,
                    executable: createinstallmediaPath,
                    arguments: createArgs,
                    parseToolPercent: true
                )
            )

            if request.isCatalina {
                guard let postSource = context.postInstallSourceAppPath else {
                    throw HelperExecutionError.invalidRequest("Brak ścieżki źródłowej do końcowego etapu Cataliny.")
                }
                let targetApp = "/Volumes/Install macOS Catalina/Install macOS Catalina.app"
                stages.append(
                    WorkflowStage(
                        key: "catalina_cleanup",
                        titleKey: HelperWorkflowLocalizationKeys.catalinaCleanupTitle,
                        statusKey: HelperWorkflowLocalizationKeys.catalinaCleanupStatus,
                        startPercent: 90,
                        endPercent: 94,
                        executable: "/bin/rm",
                        arguments: ["-rf", targetApp],
                        parseToolPercent: false
                    )
                )
                stages.append(
                    WorkflowStage(
                        key: "catalina_copy",
                        titleKey: HelperWorkflowLocalizationKeys.catalinaCopyTitle,
                        statusKey: HelperWorkflowLocalizationKeys.catalinaCopyStatus,
                        startPercent: 94,
                        endPercent: 98,
                        executable: "/usr/bin/ditto",
                        arguments: [postSource, targetApp],
                        parseToolPercent: false
                    )
                )
                stages.append(
                    WorkflowStage(
                        key: "catalina_xattr",
                        titleKey: HelperWorkflowLocalizationKeys.catalinaXattrTitle,
                        statusKey: HelperWorkflowLocalizationKeys.catalinaXattrStatus,
                        startPercent: 98,
                        endPercent: 99,
                        executable: "/usr/bin/xattr",
                        arguments: ["-dr", "com.apple.quarantine", targetApp],
                        parseToolPercent: false
                    )
                )
            }
        }

        return stages
    }

    private func runStage(_ stage: WorkflowStage) throws {
        try throwIfCancelled()
        lastStageOutputLine = nil

        let process = Process()
        if let requesterUID = request.requesterUID, requesterUID > 0 {
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["asuser", "\(requesterUID)", stage.executable] + stage.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: stage.executable)
            process.arguments = stage.arguments
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        stateQueue.sync {
            activeProcess = process
        }

        var buffer = Data()

        do {
            try process.run()
        } catch {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się uruchomić polecenia \(stage.executable): \(error.localizedDescription)"
            )
        }

        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)

            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0..<newlineRange.upperBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    handleOutputLine(line, stage: stage)
                }
            }
        }

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            handleOutputLine(line, stage: stage)
        }

        process.waitUntilExit()

        stateQueue.sync {
            activeProcess = nil
        }

        try throwIfCancelled()

        guard process.terminationStatus == 0 else {
            var description = "Polecenie \(stage.executable) zakończyło się błędem (kod \(process.terminationStatus))."
            if let lastLine = lastStageOutputLine {
                description += " Ostatni komunikat: \(lastLine)"
                if isRemovableVolumePermissionFailure(lastLine) {
                    description += " System zablokował dostęp procesu uprzywilejowanego do woluminu wymiennego (TCC/System Policy). Upewnij się, że aplikacja i helper są podpisane tym samym Team ID i zainstalowane od nowa."
                }
            }
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: process.terminationStatus,
                description: description
            )
        }
    }

    private func handleOutputLine(_ rawLine: String, stage: WorkflowStage) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        lastStageOutputLine = line

        var percent = latestPercent
        if stage.key == "ppc_restore", let mapped = mapPPCProgress(from: line) {
            percent = max(percent, mapped)
        } else if stage.parseToolPercent, let parsed = extractPercent(from: line) {
            let clamped = max(0, min(parsed, 100))
            let mapped = stage.startPercent + ((stage.endPercent - stage.startPercent) * (clamped / 100.0))
            percent = max(percent, mapped)
        }

        emit(stage: stage, percent: percent, statusKey: stage.statusKey, logLine: line)
    }

    private func mapPPCProgress(from line: String) -> Double? {
        let lowered = line.lowercased()

        if lowered.contains("validating target...done") {
            return 25
        }

        if lowered.contains("validating sizes...done") {
            return 30
        }

        guard let parsedPercent = extractPercent(from: line) else {
            return nil
        }

        let clamped = max(0, min(parsedPercent, 100))
        if clamped >= 100 {
            return 100
        }

        guard clamped >= 10 else {
            return nil
        }

        let tenStep = Int(clamped / 10.0)
        let boundedStep = min(max(tenStep, 1), 9)
        return 35 + (Double(boundedStep - 1) * 8)
    }

    private func emit(stage: WorkflowStage, percent: Double, statusKey: String, logLine: String? = nil) {
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: percent,
            statusKey: statusKey,
            logLine: logLine
        )
    }

    private func emitProgress(
        stageKey: String,
        titleKey: String,
        percent: Double,
        statusKey: String,
        logLine: String? = nil,
        shouldAdvancePercent: Bool = true
    ) {
        let clampedPercent = min(max(percent, 0), 100)
        let effectivePercent: Double
        if shouldAdvancePercent {
            latestPercent = max(latestPercent, clampedPercent)
            effectivePercent = latestPercent
        } else {
            effectivePercent = clampedPercent
        }

        let event = HelperProgressEventPayload(
            workflowID: workflowID,
            stageKey: stageKey,
            stageTitleKey: titleKey,
            percent: effectivePercent,
            statusKey: statusKey,
            logLine: logLine,
            timestamp: Date()
        )
        sendEvent(event)
    }

    private func runBestEffortTempCleanupStage() {
        let stageKey = "cleanup_temp"
        let stageTitleKey = HelperWorkflowLocalizationKeys.cleanupTempTitle
        let statusKey = HelperWorkflowLocalizationKeys.cleanupTempStatus
        let stageStart = max(latestPercent, 99)

        emitProgress(
            stageKey: stageKey,
            titleKey: stageTitleKey,
            percent: stageStart,
            statusKey: statusKey
        )

        guard !request.tempWorkPath.isEmpty else {
            emitProgress(
                stageKey: stageKey,
                titleKey: stageTitleKey,
                percent: 100,
                statusKey: statusKey
            )
            return
        }

        let tempURL = URL(fileURLWithPath: request.tempWorkPath)
        if fileManager.fileExists(atPath: tempURL.path) {
            do {
                try fileManager.removeItem(at: tempURL)
            } catch {
                emitProgress(
                    stageKey: stageKey,
                    titleKey: stageTitleKey,
                    percent: stageStart,
                    statusKey: statusKey,
                    logLine: "Cleanup temp failed: \(error.localizedDescription)",
                    shouldAdvancePercent: false
                )
            }
        }

        emitProgress(
            stageKey: stageKey,
            titleKey: stageTitleKey,
            percent: 100,
            statusKey: statusKey
        )
    }

    private func runFinalizeStage() {
        emitProgress(
            stageKey: "finalize",
            titleKey: HelperWorkflowLocalizationKeys.finalizeTitle,
            percent: 100,
            statusKey: HelperWorkflowLocalizationKeys.finalizeStatus
        )
    }

    private func ensureTempWorkDirectoryExists() throws {
        if !fileManager.fileExists(atPath: request.tempWorkPath) {
            try fileManager.createDirectory(
                atPath: request.tempWorkPath,
                withIntermediateDirectories: true
            )
        }
    }

    private func copyReplacingItem(at source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func performLocalCodesign(
        on appURL: URL,
        stageKey: String,
        stageTitleKey: String,
        statusKey: String
    ) throws {
        try runSimpleCommand(
            executable: "/usr/bin/xattr",
            arguments: ["-cr", appURL.path],
            stageKey: stageKey,
            stageTitleKey: stageTitleKey,
            statusKey: statusKey
        )

        let path = appURL.path
        let componentsToSign = [
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAInstallerUtilities.framework/Versions/A/IAInstallerUtilities",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAMiniSoftwareUpdate.framework/Versions/A/IAMiniSoftwareUpdate",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAPackageKit.framework/Versions/A/IAPackageKit",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/IAESD",
            "\(path)/Contents/Resources/createinstallmedia"
        ]

        for component in componentsToSign where fileManager.fileExists(atPath: component) {
            _ = try runSimpleCommand(
                executable: "/usr/bin/codesign",
                arguments: ["-s", "-", "-f", component],
                stageKey: stageKey,
                stageTitleKey: stageTitleKey,
                statusKey: statusKey,
                failOnNonZeroExit: false
            )
        }
    }

    @discardableResult
    private func runSimpleCommand(
        executable: String,
        arguments: [String],
        stageKey: String,
        stageTitleKey: String,
        statusKey: String,
        failOnNonZeroExit: Bool = true
    ) throws -> Int32 {
        let process = Process()
        if let requesterUID = request.requesterUID, requesterUID > 0 {
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["asuser", "\(requesterUID)", executable] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        stateQueue.sync {
            activeProcess = process
        }

        var buffer = Data()

        do {
            try process.run()
        } catch {
            stateQueue.sync {
                activeProcess = nil
            }
            throw HelperExecutionError.failed(
                stage: stageKey,
                exitCode: -1,
                description: "Nie udało się uruchomić polecenia \(executable): \(error.localizedDescription)"
            )
        }

        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)

            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0..<newlineRange.upperBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    lastStageOutputLine = trimmed
                    emitProgress(
                        stageKey: stageKey,
                        titleKey: stageTitleKey,
                        percent: latestPercent,
                        statusKey: statusKey,
                        logLine: trimmed,
                        shouldAdvancePercent: false
                    )
                }
            }
        }

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lastStageOutputLine = trimmed
                emitProgress(
                    stageKey: stageKey,
                    titleKey: stageTitleKey,
                    percent: latestPercent,
                    statusKey: statusKey,
                    logLine: trimmed,
                    shouldAdvancePercent: false
                )
            }
        }

        process.waitUntilExit()
        let terminationStatus = process.terminationStatus

        stateQueue.sync {
            activeProcess = nil
        }

        try throwIfCancelled()

        if terminationStatus != 0, failOnNonZeroExit {
            var description = "Polecenie \(executable) zakończyło się błędem (kod \(terminationStatus))."
            if let lastLine = lastStageOutputLine {
                description += " Ostatni komunikat: \(lastLine)"
            }
            throw HelperExecutionError.failed(
                stage: stageKey,
                exitCode: terminationStatus,
                description: description
            )
        }

        return terminationStatus
    }

    private func isRemovableVolumePermissionFailure(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("operation not permitted") ||
        lowered.contains("operacja nie jest dozwolona") ||
        lowered.contains("could not validate sizes - operacja nie jest dozwolona")
    }

    private func extractPercent(from line: String) -> Double? {
        let pattern = #"([0-9]{1,3}(?:\.[0-9]+)?)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        return Double(line[valueRange])
    }

    private func extractWholeDiskName(from bsdName: String) throws -> String {
        guard let range = bsdName.range(of: #"^disk[0-9]+"#, options: .regularExpression) else {
            throw HelperExecutionError.invalidRequest("Nieprawidłowy identyfikator nośnika: \(bsdName)")
        }
        return String(bsdName[range])
    }

    private func resolvePPCSourceArgument(from sourcePath: String) -> String {
        guard sourcePath.hasPrefix("/Volumes/") else {
            return sourcePath
        }

        guard let devicePath = resolveDevicePathForMountedVolume(sourcePath) else {
            return sourcePath
        }

        return devicePath
    }

    private func resolveDevicePathForMountedVolume(_ volumePath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", volumePath]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let deviceIdentifier = plist["DeviceIdentifier"] as? String,
              deviceIdentifier.hasPrefix("disk") else {
            return nil
        }

        return "/dev/\(deviceIdentifier)"
    }

    private func throwIfCancelled() throws {
        let cancelled = stateQueue.sync { isCancelled }
        if cancelled {
            throw HelperExecutionError.cancelled
        }
    }
}

private final class PrivilegedHelperService: NSObject, PrivilegedHelperToolXPCProtocol {
    weak var connection: NSXPCConnection?

    private var activeWorkflowID: String?
    private var activeExecutor: HelperWorkflowExecutor?
    private let queue = DispatchQueue(label: "macUSB.helper.service")

    func startWorkflow(_ requestData: NSData, reply: @escaping (NSString?, NSError?) -> Void) {
        queue.async {
            guard self.activeExecutor == nil else {
                let error = NSError(
                    domain: "macUSBHelper",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Helper realizuje już inne zadanie."]
                )
                reply(nil, error)
                return
            }

            let request: HelperWorkflowRequestPayload
            do {
                request = try HelperXPCCodec.decode(HelperWorkflowRequestPayload.self, from: requestData as Data)
            } catch {
                let err = NSError(
                    domain: "macUSBHelper",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowe żądanie helpera: \(error.localizedDescription)"]
                )
                reply(nil, err)
                return
            }

            let workflowID = UUID().uuidString
            let executor = HelperWorkflowExecutor(
                request: request,
                workflowID: workflowID,
                sendEvent: { [weak self] event in
                    self?.sendProgress(event)
                }
            )

            self.activeWorkflowID = workflowID
            self.activeExecutor = executor
            reply(workflowID as NSString, nil)

            DispatchQueue.global(qos: .userInitiated).async {
                let result = executor.run()
                self.queue.async {
                    self.sendResult(result)
                    self.activeWorkflowID = nil
                    self.activeExecutor = nil
                }
            }
        }
    }

    func cancelWorkflow(_ workflowID: String, reply: @escaping (Bool, NSError?) -> Void) {
        queue.async {
            guard self.activeWorkflowID == workflowID, let executor = self.activeExecutor else {
                reply(false, nil)
                return
            }
            executor.cancel()
            reply(true, nil)
        }
    }

    func queryHealth(_ reply: @escaping (Bool, NSString) -> Void) {
        let uid = getuid()
        let euid = geteuid()
        let pid = getpid()
        reply(true, "Helper odpowiada poprawnie (uid=\(uid), euid=\(euid), pid=\(pid))" as NSString)
    }

    private func sendProgress(_ event: HelperProgressEventPayload) {
        guard let client = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? PrivilegedHelperClientXPCProtocol else {
            return
        }

        guard let encoded = try? HelperXPCCodec.encode(event) else {
            return
        }
        client.receiveProgressEvent(encoded as NSData)
    }

    private func sendResult(_ result: HelperWorkflowResultPayload) {
        guard let client = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? PrivilegedHelperClientXPCProtocol else {
            return
        }

        guard let encoded = try? HelperXPCCodec.encode(result) else {
            return
        }
        client.finishWorkflow(encoded as NSData)
    }
}

private final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let service = PrivilegedHelperService()
        service.connection = newConnection

        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperToolXPCProtocol.self)
        newConnection.exportedObject = service
        newConnection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperClientXPCProtocol.self)
        newConnection.resume()

        return true
    }
}

private let delegate = HelperListenerDelegate()
private let listener = NSXPCListener(machServiceName: "com.kruszoneq.macusb.helper")
listener.delegate = delegate
listener.resume()
dispatchMain()
