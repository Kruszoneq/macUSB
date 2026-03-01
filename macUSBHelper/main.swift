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
    let isPermissionDenied: Bool?
    let permissionFailureKind: String?
}

struct HelperExternalVolumeProbePayload: Codable {
    let targetVolumePath: String
    let targetBSDName: String
    let requiresDeviceReadProbe: Bool
}

struct HelperExternalVolumeProbeResultPayload: Codable {
    let success: Bool
    let isPermissionDenied: Bool
    let failureMessage: String?
    let details: String?
}

@objc(MacUSBPrivilegedHelperToolXPCProtocol)
protocol PrivilegedHelperToolXPCProtocol {
    func startWorkflow(_ requestData: NSData, reply: @escaping (NSString?, NSError?) -> Void)
    func cancelWorkflow(_ workflowID: String, reply: @escaping (Bool, NSError?) -> Void)
    func queryHealth(_ reply: @escaping (Bool, NSString) -> Void)
    func probeExternalVolumeAccess(_ probeData: NSData, reply: @escaping (NSData?, NSError?) -> Void)
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

private enum HelperCommandExecutionContext {
    case directRoot
    case asUser(Int)

    var logLabel: String {
        switch self {
        case .directRoot:
            return "direct_root"
        case .asUser(let uid):
            return "asuser_\(uid)"
        }
    }
}

private struct PermissionFailureSignature {
    let kind: String
    let pattern: String
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
    private var lastExecutionContextLabel: String = "direct_root"
    private var lastPermissionSignature: PermissionFailureSignature?

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
                isUserCancelled: false,
                isPermissionDenied: nil,
                permissionFailureKind: nil
            )
        } catch HelperExecutionError.cancelled {
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "cancelled",
                errorCode: nil,
                errorMessage: "Operacja została anulowana przez użytkownika.",
                isUserCancelled: true,
                isPermissionDenied: nil,
                permissionFailureKind: nil
            )
        } catch HelperExecutionError.failed(let stage, let exitCode, let description) {
            runBestEffortTempCleanupStage()
            let signature = lastPermissionSignature ?? permissionFailureSignature(
                line: lastStageOutputLine,
                exitCode: exitCode,
                description: description
            )
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: stage,
                errorCode: Int(exitCode),
                errorMessage: description,
                isUserCancelled: false,
                isPermissionDenied: signature != nil,
                permissionFailureKind: signature?.kind
            )
        } catch HelperExecutionError.invalidRequest(let message) {
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "request",
                errorCode: nil,
                errorMessage: message,
                isUserCancelled: false,
                isPermissionDenied: nil,
                permissionFailureKind: nil
            )
        } catch {
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "unknown",
                errorCode: nil,
                errorMessage: error.localizedDescription,
                isUserCancelled: false,
                isPermissionDenied: nil,
                permissionFailureKind: nil
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
        let formatTargetWholeDisk = resolvePartitionTargetWholeDisk(
            fromRequestedBSDName: request.targetBSDName,
            targetVolumePath: request.targetVolumePath,
            fallbackWholeDisk: wholeDisk
        )
        emitProgress(
            stageKey: "prepare_source",
            titleKey: HelperWorkflowLocalizationKeys.prepareSourceTitle,
            percent: latestPercent,
            statusKey: HelperWorkflowLocalizationKeys.prepareSourceStatus,
            logLine: "Format target resolution: requested=\(request.targetBSDName), fallbackWhole=\(wholeDisk), resolvedWhole=\(formatTargetWholeDisk), targetVolumePath=\(request.targetVolumePath)",
            shouldAdvancePercent: false
        )
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
                    arguments: ["partitionDisk", "/dev/\(formatTargetWholeDisk)", "GPT", "HFS+", request.targetLabel, "100%"],
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
                    arguments: ["partitionDisk", "/dev/\(formatTargetWholeDisk)", "APM", "HFS+", "PPC", "100%"],
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
        lastPermissionSignature = nil

        let process = Process()
        try configureProcess(
            process,
            executable: stage.executable,
            arguments: stage.arguments,
            stageKey: stage.key,
            stageTitleKey: stage.titleKey,
            statusKey: stage.statusKey
        )

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
            drainBufferedOutputLines(from: &buffer) { line in
                handleOutputLine(line, stage: stage)
            }
        }

        if !buffer.isEmpty,
           let line = String(data: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty {
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
            let signature = permissionFailureSignature(
                line: lastStageOutputLine,
                exitCode: process.terminationStatus,
                description: description
            )
            if let signature {
                lastPermissionSignature = signature
                emitProgress(
                    stageKey: stage.key,
                    titleKey: stage.titleKey,
                    percent: latestPercent,
                    statusKey: stage.statusKey,
                    logLine: "PERMISSION_DENY_SIGNATURE stage=\(stage.key) code=\(process.terminationStatus) pattern=\(signature.pattern) exec_context=\(lastExecutionContextLabel)",
                    shouldAdvancePercent: false
                )
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
        if let signature = permissionFailureSignature(line: line, exitCode: nil, description: line) {
            lastPermissionSignature = signature
            emitProgress(
                stageKey: stage.key,
                titleKey: stage.titleKey,
                percent: latestPercent,
                statusKey: stage.statusKey,
                logLine: "PERMISSION_DENY_SIGNATURE stage=\(stage.key) code=n/a pattern=\(signature.pattern) exec_context=\(lastExecutionContextLabel)",
                shouldAdvancePercent: false
            )
        }

        var percent = latestPercent
        if stage.key == "ppc_restore", let mapped = mapPPCProgress(from: line) {
            percent = max(percent, mapped)
        } else if stage.parseToolPercent, let parsed = extractToolPercent(from: line, stageKey: stage.key) {
            let clamped = max(0, min(parsed, 100))
            let mapped = stage.startPercent + ((stage.endPercent - stage.startPercent) * (clamped / 100.0))
            percent = max(percent, mapped)
        }

        emit(stage: stage, percent: percent, statusKey: stage.statusKey, logLine: line)
    }

    private func extractToolPercent(from line: String, stageKey: String) -> Double? {
        if stageKey == "createinstallmedia" {
            let lowered = line.lowercased()
            if lowered.contains("erasing disk") {
                return nil
            }
        }

        return extractPercent(from: line)
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
        lastPermissionSignature = nil
        let process = Process()
        try configureProcess(
            process,
            executable: executable,
            arguments: arguments,
            stageKey: stageKey,
            stageTitleKey: stageTitleKey,
            statusKey: statusKey
        )

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
            drainBufferedOutputLines(from: &buffer) { line in
                lastStageOutputLine = line
                emitProgress(
                    stageKey: stageKey,
                    titleKey: stageTitleKey,
                    percent: latestPercent,
                    statusKey: statusKey,
                    logLine: line,
                    shouldAdvancePercent: false
                )
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
            let signature = permissionFailureSignature(
                line: lastStageOutputLine,
                exitCode: terminationStatus,
                description: description
            )
            if let signature {
                lastPermissionSignature = signature
                emitProgress(
                    stageKey: stageKey,
                    titleKey: stageTitleKey,
                    percent: latestPercent,
                    statusKey: statusKey,
                    logLine: "PERMISSION_DENY_SIGNATURE stage=\(stageKey) code=\(terminationStatus) pattern=\(signature.pattern) exec_context=\(lastExecutionContextLabel)",
                    shouldAdvancePercent: false
                )
            }
            throw HelperExecutionError.failed(
                stage: stageKey,
                exitCode: terminationStatus,
                description: description
            )
        }

        return terminationStatus
    }

    private func configureProcess(
        _ process: Process,
        executable: String,
        arguments: [String],
        stageKey: String,
        stageTitleKey: String,
        statusKey: String
    ) throws {
        let context = commandExecutionContext(for: executable)
        switch context {
        case .directRoot:
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        case .asUser(let requesterUID):
            if shouldRunDirectlyInHelper(executable) {
                let message = "Naruszenie polityki wykonania: polecenie storage trafiło do asuser (\(executable))."
                emitProgress(
                    stageKey: stageKey,
                    titleKey: stageTitleKey,
                    percent: latestPercent,
                    statusKey: statusKey,
                    logLine: message,
                    shouldAdvancePercent: false
                )
                throw HelperExecutionError.failed(
                    stage: stageKey,
                    exitCode: 251,
                    description: message
                )
            }
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["asuser", "\(requesterUID)", executable] + arguments
        }

        lastExecutionContextLabel = context.logLabel

        emitProgress(
            stageKey: stageKey,
            titleKey: stageTitleKey,
            percent: latestPercent,
            statusKey: statusKey,
            logLine: "Execution context: \(context.logLabel); command=\(executable)",
            shouldAdvancePercent: false
        )
    }

    private func commandExecutionContext(for executable: String) -> HelperCommandExecutionContext {
        if shouldRunDirectlyInHelper(executable) {
            return .directRoot
        }

        if let requesterUID = request.requesterUID, requesterUID > 0 {
            return .asUser(requesterUID)
        }

        return .directRoot
    }

    private func shouldRunDirectlyInHelper(_ executable: String) -> Bool {
        let normalizedExecutable = executable.lowercased()
        if normalizedExecutable == "/usr/sbin/asr" || normalizedExecutable == "/usr/sbin/diskutil" {
            return true
        }

        return normalizedExecutable.hasSuffix("/createinstallmedia")
    }

    private func isRemovableVolumePermissionFailure(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("operation not permitted") ||
        lowered.contains("operacja nie jest dozwolona") ||
        lowered.contains("could not validate sizes - operacja nie jest dozwolona")
    }

    private func permissionFailureSignature(
        line: String?,
        exitCode: Int32?,
        description: String
    ) -> PermissionFailureSignature? {
        if let line, let signature = permissionFailureSignatureFromText(line) {
            return signature
        }

        let loweredDescription = description.lowercased()
        if loweredDescription.contains("system policy") && loweredDescription.contains("deny") {
            return PermissionFailureSignature(kind: "system_policy_deny", pattern: "system_policy_deny")
        }
        if loweredDescription.contains("operation not permitted") ||
            loweredDescription.contains("operacja nie jest dozwolona") {
            return PermissionFailureSignature(kind: "asr_permission", pattern: "operation_not_permitted")
        }

        if let exitCode, exitCode == 250 || exitCode == 251 {
            return PermissionFailureSignature(kind: "createinstallmedia_\(exitCode)", pattern: "exit_code_\(exitCode)")
        }

        return nil
    }

    private func permissionFailureSignatureFromText(_ text: String) -> PermissionFailureSignature? {
        let lowered = text.lowercased()

        if lowered.contains("system policy") && lowered.contains("deny") {
            return PermissionFailureSignature(kind: "system_policy_deny", pattern: "system_policy_deny")
        }
        if lowered.contains("could not validate sizes - operacja nie jest dozwolona") {
            return PermissionFailureSignature(kind: "asr_permission", pattern: "asr_validate_sizes_operation_not_permitted")
        }
        if lowered.contains("operation not permitted") || lowered.contains("operacja nie jest dozwolona") {
            return PermissionFailureSignature(kind: "asr_permission", pattern: "operation_not_permitted")
        }
        if lowered.contains("ia app name cookie write failed") {
            return PermissionFailureSignature(kind: "createinstallmedia_250", pattern: "ia_cookie_write_failed")
        }
        if lowered.contains("bless") && lowered.contains("failed") {
            return PermissionFailureSignature(kind: "createinstallmedia_250", pattern: "bless_failed")
        }

        return nil
    }

    private func drainBufferedOutputLines(from buffer: inout Data, handleLine: (String) -> Void) {
        while let separatorIndex = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer.subdata(in: buffer.startIndex..<separatorIndex)
            var removeUpperBound = separatorIndex + 1

            if buffer[separatorIndex] == 0x0D,
               removeUpperBound < buffer.endIndex,
               buffer[removeUpperBound] == 0x0A {
                removeUpperBound += 1
            }

            buffer.removeSubrange(buffer.startIndex..<removeUpperBound)

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else {
                continue
            }

            handleLine(line)
        }
    }

    private func extractPercent(from line: String) -> Double? {
        if let standardPercent = extractLastNumberToken(
            from: line,
            pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)%"#
        ) {
            return standardPercent
        }

        // asr restore can emit progress in dotted form: "....10....20...."
        return extractLastNumberToken(
            from: line,
            pattern: #"\.{2,}\s*([0-9]{1,3})(?=\s*\.{2,})"#
        )
    }

    private func extractLastNumberToken(from line: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: line.utf16.count)
        let matches = regex.matches(in: line, options: [], range: range)
        guard let lastMatch = matches.last,
              lastMatch.numberOfRanges > 1,
              let valueRange = Range(lastMatch.range(at: 1), in: line) else {
            return nil
        }

        let rawValue = String(line[valueRange]).replacingOccurrences(of: ",", with: ".")
        return Double(rawValue)
    }

    private func resolvePartitionTargetWholeDisk(
        fromRequestedBSDName requestedBSDName: String,
        targetVolumePath: String,
        fallbackWholeDisk: String
    ) -> String {
        let requestedWhole = (try? extractWholeDiskName(from: requestedBSDName)) ?? fallbackWholeDisk
        var containerReferences: [String] = []
        let candidateArguments: [[String]] = [
            ["info", "-plist", targetVolumePath],
            ["info", "-plist", "/dev/\(requestedBSDName)"],
            ["info", "-plist", "/dev/\(requestedWhole)"],
            ["list", "-plist", "/dev/\(requestedWhole)"]
        ]

        for arguments in candidateArguments {
            guard let plist = runDiskutilPlistCommand(arguments: arguments) else { continue }
            containerReferences.append(contentsOf: extractAPFSContainerReferences(from: plist))
            if let physicalWhole = extractAPFSPhysicalStoreWholeDisk(from: plist) {
                return physicalWhole
            }
            if let parentWhole = extractParentWholeDisk(from: plist),
               parentWhole != requestedWhole {
                return parentWhole
            }
        }

        let uniqueContainerReferences = Array(Set(containerReferences))
        for containerRef in uniqueContainerReferences {
            let normalizedContainerRef = (try? extractWholeDiskName(from: containerRef)) ?? requestedWhole
            let apfsCandidates: [[String]] = [
                ["apfs", "list", "-plist", "/dev/\(normalizedContainerRef)"],
                ["info", "-plist", "/dev/\(normalizedContainerRef)"]
            ]

            for arguments in apfsCandidates {
                guard let plist = runDiskutilPlistCommand(arguments: arguments) else { continue }
                if let physicalWhole = extractAPFSPhysicalStoreWholeDisk(from: plist) {
                    return physicalWhole
                }
                if let parentWhole = extractParentWholeDisk(from: plist),
                   parentWhole != requestedWhole {
                    return parentWhole
                }
            }
        }

        return fallbackWholeDisk
    }

    private func runDiskutilPlistCommand(arguments: [String]) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
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

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private func extractParentWholeDisk(from plist: [String: Any]) -> String? {
        if let parent = plist["ParentWholeDisk"] as? String,
           let normalized = try? extractWholeDiskName(from: parent) {
            return normalized
        }

        for value in plist.values {
            if let childPlist = value as? [String: Any],
               let found = extractParentWholeDisk(from: childPlist) {
                return found
            }

            if let childArray = value as? [[String: Any]] {
                for child in childArray {
                    if let found = extractParentWholeDisk(from: child) {
                        return found
                    }
                }
            }
        }

        return nil
    }

    private func extractAPFSPhysicalStoreWholeDisk(from plist: [String: Any]) -> String? {
        if let stores = plist["APFSPhysicalStores"] as? [[String: Any]] {
            for store in stores {
                if let identifier = store["DeviceIdentifier"] as? String,
                   let whole = try? extractWholeDiskName(from: identifier) {
                    return whole
                }
            }
        }

        if let stores = plist["APFSPhysicalStores"] as? [String] {
            for identifier in stores {
                if let whole = try? extractWholeDiskName(from: identifier) {
                    return whole
                }
            }
        }

        for value in plist.values {
            if let childPlist = value as? [String: Any],
               let found = extractAPFSPhysicalStoreWholeDisk(from: childPlist) {
                return found
            }

            if let childArray = value as? [[String: Any]] {
                for child in childArray {
                    if let found = extractAPFSPhysicalStoreWholeDisk(from: child) {
                        return found
                    }
                }
            }
        }

        return nil
    }

    private func extractAPFSContainerReferences(from plist: [String: Any]) -> [String] {
        var result: [String] = []

        if let containerRef = plist["APFSContainerReference"] as? String {
            result.append(containerRef)
        }

        if let containerRefs = plist["APFSContainerReference"] as? [String] {
            result.append(contentsOf: containerRefs)
        }

        for value in plist.values {
            if let childPlist = value as? [String: Any] {
                result.append(contentsOf: extractAPFSContainerReferences(from: childPlist))
            } else if let childArray = value as? [[String: Any]] {
                for child in childArray {
                    result.append(contentsOf: extractAPFSContainerReferences(from: child))
                }
            }
        }

        return result
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

    func probeExternalVolumeAccess(_ probeData: NSData, reply: @escaping (NSData?, NSError?) -> Void) {
        queue.async {
            let payload: HelperExternalVolumeProbePayload
            do {
                payload = try HelperXPCCodec.decode(HelperExternalVolumeProbePayload.self, from: probeData as Data)
            } catch {
                let err = NSError(
                    domain: "macUSBHelper",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowe żądanie probe helpera: \(error.localizedDescription)"]
                )
                reply(nil, err)
                return
            }

            let result = self.performExternalVolumeProbe(payload)
            do {
                let encoded = try HelperXPCCodec.encode(result)
                reply(encoded as NSData, nil)
            } catch {
                let err = NSError(
                    domain: "macUSBHelper",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Nie udało się zakodować wyniku probe helpera: \(error.localizedDescription)"]
                )
                reply(nil, err)
            }
        }
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

    private func performExternalVolumeProbe(_ payload: HelperExternalVolumeProbePayload) -> HelperExternalVolumeProbeResultPayload {
        if payload.targetVolumePath.hasPrefix("/Volumes/") {
            let probeURL = URL(fileURLWithPath: payload.targetVolumePath)
                .appendingPathComponent(".macusb-helper-write-probe-\(UUID().uuidString)")

            do {
                try Data("macUSBHelper".utf8).write(to: probeURL, options: .atomic)
                try? FileManager.default.removeItem(at: probeURL)
            } catch {
                let nsError = error as NSError
                let underlyingCode = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
                let code = underlyingCode ?? nsError.code
                return HelperExternalVolumeProbeResultPayload(
                    success: false,
                    isPermissionDenied: code == Int(EPERM) || code == Int(EACCES),
                    failureMessage: "Helper probe: błąd zapisu testowego na nośniku.",
                    details: "\(error.localizedDescription) (code=\(code))"
                )
            }
        }

        if payload.requiresDeviceReadProbe {
            guard let wholeDisk = extractWholeDiskName(from: payload.targetBSDName) else {
                return HelperExternalVolumeProbeResultPayload(
                    success: false,
                    isPermissionDenied: false,
                    failureMessage: "Helper probe: nieprawidłowy identyfikator nośnika.",
                    details: payload.targetBSDName
                )
            }

            let rawDevicePath = "/dev/r\(wholeDisk)"
            let fd = open(rawDevicePath, O_RDONLY)
            if fd < 0 {
                let code = errno
                let details = "\(String(cString: strerror(code))) (code=\(code), path=\(rawDevicePath))"
                return HelperExternalVolumeProbeResultPayload(
                    success: false,
                    isPermissionDenied: code == EPERM || code == EACCES,
                    failureMessage: "Helper probe: błąd odczytu urządzenia blokowego.",
                    details: details
                )
            }
            close(fd)
        }

        return HelperExternalVolumeProbeResultPayload(
            success: true,
            isPermissionDenied: false,
            failureMessage: nil,
            details: nil
        )
    }

    private func extractWholeDiskName(from bsdName: String) -> String? {
        guard let range = bsdName.range(of: #"^disk[0-9]+"#, options: .regularExpression) else {
            return nil
        }
        return String(bsdName[range])
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
