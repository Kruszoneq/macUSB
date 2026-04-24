import Foundation
import Darwin

extension HelperWorkflowExecutor {
    func runStage(_ stage: WorkflowStage) throws {
        try throwIfCancelled()
        lastStageOutputLine = nil

        if stage.key == "linux_unmount_target" {
            try runLinuxUnmountTargetStage(stage)
            return
        }

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
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: process.terminationStatus,
                description: description
            )
        }
    }
    func runBestEffortTempCleanupStage() {
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
    func runFinalizeStage() {
        emitProgress(
            stageKey: "finalize",
            titleKey: HelperWorkflowLocalizationKeys.finalizeTitle,
            percent: 100,
            statusKey: HelperWorkflowLocalizationKeys.finalizeStatus
        )
    }
    func ensureTempWorkDirectoryExists() throws {
        if !fileManager.fileExists(atPath: request.tempWorkPath) {
            try fileManager.createDirectory(
                atPath: request.tempWorkPath,
                withIntermediateDirectories: true
            )
        }
    }
    func copyReplacingItem(at source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
    func performLocalCodesign(
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
    func runSimpleCommand(
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
            throw HelperExecutionError.failed(
                stage: stageKey,
                exitCode: terminationStatus,
                description: description
            )
        }

        return terminationStatus
    }
    func isRemovableVolumePermissionFailure(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("operation not permitted") ||
        lowered.contains("operacja nie jest dozwolona") ||
        lowered.contains("could not validate sizes - operacja nie jest dozwolona")
    }
    func throwIfCancelled() throws {
        let cancelled = stateQueue.sync { isCancelled }
        if cancelled {
            throw HelperExecutionError.cancelled
        }
    }
}
