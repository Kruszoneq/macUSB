import Foundation

extension HelperWorkflowExecutor {
    private static let linuxUnmountBusyPromptMarker = "linux_unmount_busy_prompt"

    func shouldDeferCleanupForLinuxUnmountPrompt(failedStage: String, description: String) -> Bool {
        guard failedStage == "linux_unmount_target" else { return false }
        guard !request.linuxForceUnmount else { return false }
        return description.lowercased().contains(Self.linuxUnmountBusyPromptMarker)
    }

    func runLinuxUnmountTargetStage(_ stage: WorkflowStage) throws {
        let targetDevice = stage.arguments.last ?? ""
        guard !targetDevice.isEmpty else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się ustalić urządzenia do odmontowania."
            )
        }

        if request.linuxForceUnmount {
            let status = try runLinuxUnmountCommand(
                stage: stage,
                arguments: ["unmountDisk", "force", targetDevice]
            )
            guard status.success else {
                var description = "Wymuszone odmontowanie nośnika nie powiodło się (kod \(status.exitCode))."
                if let line = status.lastLine {
                    description += " Ostatni komunikat: \(line)"
                }
                throw HelperExecutionError.failed(stage: stage.key, exitCode: status.exitCode, description: description)
            }
            return
        }

        let retryDelaySeconds = 2
        let retryCount = 3
        let totalAttempts = retryCount + 1

        for attempt in 1...totalAttempts {
            let status = try runLinuxUnmountCommand(
                stage: stage,
                arguments: ["unmountDisk", targetDevice]
            )

            if status.success {
                return
            }

            if status.isBusyFailure, attempt <= retryCount {
                emitProgress(
                    stageKey: stage.key,
                    titleKey: stage.titleKey,
                    percent: latestPercent,
                    statusKey: stage.statusKey,
                    logLine: "Linux unmount retry \(attempt)/\(retryCount): nośnik zajęty, ponawiam za \(retryDelaySeconds)s.",
                    shouldAdvancePercent: false
                )
                try waitLinuxUnmountRetryDelay(seconds: retryDelaySeconds)
                continue
            }

            if status.isBusyFailure {
                let description = "Nie udało się odmontować nośnika, ponieważ jest używany przez inny proces. \(Self.linuxUnmountBusyPromptMarker)"
                throw HelperExecutionError.failed(stage: stage.key, exitCode: status.exitCode, description: description)
            }

            var description = "Nie udało się odmontować nośnika (kod \(status.exitCode))."
            if let line = status.lastLine {
                description += " Ostatni komunikat: \(line)"
            }
            throw HelperExecutionError.failed(stage: stage.key, exitCode: status.exitCode, description: description)
        }
    }

    private func runLinuxUnmountCommand(stage: WorkflowStage, arguments: [String]) throws -> (success: Bool, exitCode: Int32, isBusyFailure: Bool, lastLine: String?) {
        let process = Process()
        if let requesterUID = request.requesterUID, requesterUID > 0 {
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["asuser", "\(requesterUID)", "/usr/sbin/diskutil"] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = arguments
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        stateQueue.sync {
            activeProcess = process
        }

        var buffer = Data()
        var isBusyFailure = false
        var lastLine: String?

        do {
            try process.run()
        } catch {
            stateQueue.sync {
                activeProcess = nil
            }
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się uruchomić polecenia /usr/sbin/diskutil: \(error.localizedDescription)"
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
                lastLine = line
                if isLinuxUnmountBusyLine(line) {
                    isBusyFailure = true
                }
                emitProgress(
                    stageKey: stage.key,
                    titleKey: stage.titleKey,
                    percent: latestPercent,
                    statusKey: stage.statusKey,
                    logLine: line,
                    shouldAdvancePercent: false
                )
            }
        }

        if !buffer.isEmpty,
           let line = String(data: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty {
            lastStageOutputLine = line
            lastLine = line
            if isLinuxUnmountBusyLine(line) {
                isBusyFailure = true
            }
            emitProgress(
                stageKey: stage.key,
                titleKey: stage.titleKey,
                percent: latestPercent,
                statusKey: stage.statusKey,
                logLine: line,
                shouldAdvancePercent: false
            )
        }

        process.waitUntilExit()
        let exitCode = process.terminationStatus

        stateQueue.sync {
            activeProcess = nil
        }

        try throwIfCancelled()

        return (
            success: exitCode == 0,
            exitCode: exitCode,
            isBusyFailure: isBusyFailure,
            lastLine: lastLine
        )
    }

    private func waitLinuxUnmountRetryDelay(seconds: Int) throws {
        guard seconds > 0 else { return }
        for _ in 0..<(seconds * 10) {
            try throwIfCancelled()
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func isLinuxUnmountBusyLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("at least one volume could not be unmounted")
            || lowered.contains("unmount was dissented by pid")
            || lowered.contains("resource busy")
            || lowered.contains("device busy")
    }
}
