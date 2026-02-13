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
    let sourcePath: String
    let targetVolumePath: String
    let targetBSDName: String
    let targetLabel: String
    let needsPreformat: Bool
    let isCatalina: Bool
    let requiresApplicationPathArg: Bool
    let postInstallSourceAppPath: String?
}

struct HelperProgressEventPayload: Codable {
    let workflowID: String
    let stageKey: String
    let stageTitle: String
    let percent: Double
    let statusText: String
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
    let title: String
    let startPercent: Double
    let endPercent: Double
    let executable: String
    let arguments: [String]
    let parseToolPercent: Bool
}

private final class HelperWorkflowExecutor {
    private let request: HelperWorkflowRequestPayload
    private let workflowID: String
    private let sendEvent: (HelperProgressEventPayload) -> Void

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
            let stages = try buildStages()
            for stage in stages {
                try throwIfCancelled()
                emit(stage: stage, percent: stage.startPercent, status: "Rozpoczynanie etapu")
                try runStage(stage)
                emit(stage: stage, percent: stage.endPercent, status: "Etap zakończony")
            }

            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: true,
                failedStage: nil,
                errorCode: nil,
                errorMessage: nil,
                isUserCancelled: false
            )
        } catch HelperExecutionError.cancelled {
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "cancelled",
                errorCode: nil,
                errorMessage: "Operacja została anulowana przez użytkownika.",
                isUserCancelled: true
            )
        } catch HelperExecutionError.failed(let stage, let exitCode, let description) {
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: stage,
                errorCode: Int(exitCode),
                errorMessage: description,
                isUserCancelled: false
            )
        } catch HelperExecutionError.invalidRequest(let message) {
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "request",
                errorCode: nil,
                errorMessage: message,
                isUserCancelled: false
            )
        } catch {
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

    private func buildStages() throws -> [WorkflowStage] {
        let wholeDisk = try extractWholeDiskName(from: request.targetBSDName)
        let rawTargetPath = request.targetVolumePath
        var effectiveTargetPath = rawTargetPath

        var stages: [WorkflowStage] = []

        if request.workflowKind != .ppc && request.needsPreformat {
            stages.append(
                WorkflowStage(
                    key: "preformat",
                    title: "Formatowanie nośnika (GPT + HFS+)",
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
                    title: "Skanowanie obrazu",
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.needsPreformat ? 50 : 35,
                    executable: "/usr/sbin/asr",
                    arguments: ["imagescan", "--source", request.sourcePath],
                    parseToolPercent: true
                )
            )
            stages.append(
                WorkflowStage(
                    key: "restore",
                    title: "Przywracanie obrazu na USB",
                    startPercent: request.needsPreformat ? 50 : 35,
                    endPercent: 98,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", request.sourcePath, "--target", effectiveTargetPath, "--erase", "--noprompt", "--noverify"],
                    parseToolPercent: true
                )
            )

        case .mavericks:
            stages.append(
                WorkflowStage(
                    key: "imagescan",
                    title: "Skanowanie obrazu",
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.needsPreformat ? 50 : 35,
                    executable: "/usr/sbin/asr",
                    arguments: ["imagescan", "--source", request.sourcePath],
                    parseToolPercent: true
                )
            )
            stages.append(
                WorkflowStage(
                    key: "restore",
                    title: "Przywracanie obrazu na USB",
                    startPercent: request.needsPreformat ? 50 : 35,
                    endPercent: 98,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", request.sourcePath, "--target", effectiveTargetPath, "--erase", "--noprompt", "--noverify"],
                    parseToolPercent: true
                )
            )

        case .ppc:
            stages.append(
                WorkflowStage(
                    key: "ppc_format",
                    title: "Formatowanie nośnika (APM + HFS+)",
                    startPercent: 0,
                    endPercent: 35,
                    executable: "/usr/sbin/diskutil",
                    arguments: ["partitionDisk", "/dev/\(wholeDisk)", "APM", "HFS+", "PPC", "100%"],
                    parseToolPercent: false
                )
            )

            let ppcRestoreSource = resolvePPCSourceArgument(from: request.sourcePath)
            stages.append(
                WorkflowStage(
                    key: "ppc_restore",
                    title: "Przywracanie obrazu na nośnik PPC",
                    startPercent: 35,
                    endPercent: 96,
                    executable: "/usr/sbin/asr",
                    arguments: ["restore", "--source", ppcRestoreSource, "--target", "/Volumes/PPC", "--erase", "--noverify", "--noprompt", "--verbose"],
                    parseToolPercent: true
                )
            )

        case .standard:
            let createinstallmediaPath = (request.sourcePath as NSString).appendingPathComponent("Contents/Resources/createinstallmedia")
            var createArgs: [String] = ["--volume", effectiveTargetPath]
            if request.requiresApplicationPathArg {
                createArgs.append(contentsOf: ["--applicationpath", request.sourcePath])
            }
            createArgs.append("--nointeraction")

            stages.append(
                WorkflowStage(
                    key: "createinstallmedia",
                    title: "Tworzenie instalatora USB",
                    startPercent: request.needsPreformat ? 30 : 15,
                    endPercent: request.isCatalina ? 90 : 98,
                    executable: createinstallmediaPath,
                    arguments: createArgs,
                    parseToolPercent: true
                )
            )

            if request.isCatalina {
                guard let postSource = request.postInstallSourceAppPath else {
                    throw HelperExecutionError.invalidRequest("Brak ścieżki źródłowej do końcowego etapu Cataliny.")
                }
                let targetApp = "/Volumes/Install macOS Catalina/Install macOS Catalina.app"
                stages.append(
                    WorkflowStage(
                        key: "catalina_cleanup",
                        title: "Czyszczenie nośnika docelowego",
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
                        title: "Kopiowanie finalnych plików instalatora",
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
                        title: "Usuwanie atrybutu kwarantanny",
                        startPercent: 98,
                        endPercent: 99,
                        executable: "/usr/bin/xattr",
                        arguments: ["-dr", "com.apple.quarantine", targetApp],
                        parseToolPercent: false
                    )
                )
            }
        }

        stages.append(
            WorkflowStage(
                key: "finalize",
                title: "Finalizacja",
                startPercent: 99,
                endPercent: 100,
                executable: "/usr/bin/true",
                arguments: [],
                parseToolPercent: false
            )
        )

        return stages
    }

    private func runStage(_ stage: WorkflowStage) throws {
        try throwIfCancelled()
        lastStageOutputLine = nil

        if stage.executable == "/usr/bin/true" {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: stage.executable)
        process.arguments = stage.arguments

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
        if stage.parseToolPercent, let parsed = extractPercent(from: line) {
            let clamped = max(0, min(parsed, 100))
            let mapped = stage.startPercent + ((stage.endPercent - stage.startPercent) * (clamped / 100.0))
            percent = max(percent, mapped)
        }

        emit(stage: stage, percent: percent, status: line, logLine: line)
    }

    private func emit(stage: WorkflowStage, percent: Double, status: String, logLine: String? = nil) {
        latestPercent = max(latestPercent, min(percent, 100))

        let event = HelperProgressEventPayload(
            workflowID: workflowID,
            stageKey: stage.key,
            stageTitle: stage.title,
            percent: latestPercent,
            statusText: status,
            logLine: logLine,
            timestamp: Date()
        )
        sendEvent(event)
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
