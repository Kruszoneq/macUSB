import Foundation

extension HelperWorkflowExecutor {
    func macUSBootUnmountDisk(_ wholeDisk: String, stage: WorkflowStage) throws {
        let result = try runMacUSBootDiskutil(
            arguments: ["unmountDisk", "/dev/\(wholeDisk)"],
            stage: stage,
            statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootUnmounting,
            asRequester: false,
            logOutput: true
        )
        guard result.exitCode == 0 else {
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess(
                "diskutil unmountDisk failed exit=\(result.exitCode), stderr=\(result.stderr)"
            )
        }
    }

    func macUSBootConfirmDiskUnmounted(_ wholeDisk: String, stage: WorkflowStage) throws {
        let result = try runMacUSBootDiskutil(
            arguments: ["list", "-plist", "/dev/\(wholeDisk)"],
            stage: stage,
            statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootUnmounting,
            asRequester: false,
            logOutput: false
        )
        guard result.exitCode == 0,
              let plist = try? PropertyListSerialization.propertyList(
                from: result.stdoutData,
                options: [],
                format: nil
              ) else {
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess("cannot inspect target mount state")
        }
        guard !macUSBootPlistContainsMountPoint(plist) else {
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess("target has a mounted partition")
        }
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootUnmounting,
            logLine: "macUSBoot mount inspection completed: target=\(wholeDisk), mountedPartitions=0",
            shouldAdvancePercent: false
        )
    }

    func macUSBootAttemptFinalMount(_ wholeDisk: String, stage: WorkflowStage) {
        do {
            let result = try runMacUSBootDiskutil(
                arguments: ["mountDisk", "/dev/\(wholeDisk)"],
                stage: stage,
                statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootRemounting,
                asRequester: true,
                logOutput: true
            )
            let prefix = result.exitCode == 0 ? "completed" : "warning"
            emitProgress(
                stageKey: stage.key,
                titleKey: stage.titleKey,
                percent: latestPercent,
                statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootRemounting,
                logLine: "macUSBoot final mount \(prefix): target=\(wholeDisk), exit=\(result.exitCode)",
                shouldAdvancePercent: false
            )
        } catch {
            emitProgress(
                stageKey: stage.key,
                titleKey: stage.titleKey,
                percent: latestPercent,
                statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootRemounting,
                logLine: "macUSBoot final mount warning: target=\(wholeDisk), error=\(error.localizedDescription)",
                shouldAdvancePercent: false
            )
        }
    }

    private func runMacUSBootDiskutil(
        arguments: [String],
        stage: WorkflowStage,
        statusKey: String,
        asRequester: Bool,
        logOutput: Bool
    ) throws -> (exitCode: Int32, stdoutData: Data, stderr: String) {
        let logicalCommand = "/usr/sbin/diskutil " + arguments.joined(separator: " ")
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: statusKey,
            logLine: "macUSBoot process started: \(logicalCommand)",
            shouldAdvancePercent: false
        )

        let process = Process()
        if asRequester, let requesterUID = request.requesterUID, requesterUID > 0 {
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["asuser", "\(requesterUID)", "/usr/sbin/diskutil"] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = arguments
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stateQueue.sync { activeProcess = process }

        do {
            try process.run()
        } catch {
            stateQueue.sync { activeProcess = nil }
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess(
                "cannot start \(logicalCommand): \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()
        stateQueue.sync { activeProcess = nil }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if logOutput {
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            for line in (stdout + "\n" + stderr).split(separator: "\n") {
                emitProgress(
                    stageKey: stage.key,
                    titleKey: stage.titleKey,
                    percent: latestPercent,
                    statusKey: statusKey,
                    logLine: "macUSBoot process output: \(line)",
                    shouldAdvancePercent: false
                )
            }
        }
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: statusKey,
            logLine: "macUSBoot process completed: \(logicalCommand), exit=\(process.terminationStatus)",
            shouldAdvancePercent: false
        )
        return (process.terminationStatus, stdoutData, stderr)
    }

    private func macUSBootPlistContainsMountPoint(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            if let mountPoint = dictionary["MountPoint"] as? String, !mountPoint.isEmpty {
                return true
            }
            return dictionary.values.contains(where: macUSBootPlistContainsMountPoint)
        }
        if let array = value as? [Any] {
            return array.contains(where: macUSBootPlistContainsMountPoint)
        }
        return false
    }
}
