import Foundation

extension HelperWorkflowExecutor {
    private static let windowsUnmountForcePromptMarker = "windows_unmount_force_prompt"

    func shouldDeferCleanupForWindowsUnmountPrompt(failedStage: String, description: String) -> Bool {
        guard request.workflowKind == .windows else { return false }
        guard failedStage == "windows_prepare_target" else { return false }
        guard !request.windowsForceUnmount else { return false }
        return description.lowercased().contains(Self.windowsUnmountForcePromptMarker)
    }

    func runWindowsPrepareTargetStage(_ stage: WorkflowStage) throws {
        let wholeDisk = try extractWholeDiskName(from: request.targetBSDName)
        let targetDevice = "/dev/\(wholeDisk)"

        if request.windowsForceUnmount {
            let forcedUnmountStatus = try runWindowsUnmountCommand(
                stage: stage,
                arguments: ["unmountDisk", "force", targetDevice]
            )

            guard forcedUnmountStatus.success else {
                var description = "Wymuszone odmontowanie nośnika nie powiodło się (kod \(forcedUnmountStatus.exitCode))."
                if let line = forcedUnmountStatus.lastLine {
                    description += " Ostatni komunikat: \(line)"
                }
                throw HelperExecutionError.failed(stage: stage.key, exitCode: forcedUnmountStatus.exitCode, description: description)
            }
        } else {
            let retryDelaySeconds = 2
            let retryCount = 3
            let totalAttempts = retryCount + 1

            var lastFailure: (exitCode: Int32, lastLine: String?, isBusyFailure: Bool)?
            for attempt in 1...totalAttempts {
                let unmountStatus = try runWindowsUnmountCommand(
                    stage: stage,
                    arguments: ["unmountDisk", targetDevice]
                )

                if unmountStatus.success {
                    break
                }

                lastFailure = (
                    exitCode: unmountStatus.exitCode,
                    lastLine: unmountStatus.lastLine,
                    isBusyFailure: unmountStatus.isBusyFailure
                )

                if attempt <= retryCount {
                    emitProgress(
                        stageKey: stage.key,
                        titleKey: stage.titleKey,
                        percent: latestPercent,
                        statusKey: stage.statusKey,
                        logLine: "Windows unmount retry \(attempt)/\(retryCount): odmontowanie nieudane (kod \(unmountStatus.exitCode)), ponawiam za \(retryDelaySeconds)s.",
                        shouldAdvancePercent: false
                    )
                    try waitWindowsUnmountRetryDelay(seconds: retryDelaySeconds)
                    continue
                }
            }

            if let failure = lastFailure {
                var description = "Nie udało się odmontować nośnika przed formatowaniem. \(Self.windowsUnmountForcePromptMarker)"
                description += " Kod: \(failure.exitCode)."
                if failure.isBusyFailure {
                    description += " Wykryto sygnał zajętego urządzenia."
                }
                if let line = failure.lastLine {
                    description += " Ostatni komunikat: \(line)"
                }
                throw HelperExecutionError.failed(stage: stage.key, exitCode: failure.exitCode, description: description)
            }
        }

        try runWindowsFormatCommand(stage: stage, wholeDisk: wholeDisk)
        let mountPath = try waitForWindowsTargetVolumeMountPath(
            stage: stage,
            wholeDisk: wholeDisk,
            preferredVolumeName: request.targetLabel
        )
        windowsPreparedTargetVolumePath = mountPath

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows target prepared: disk=\(wholeDisk), label=\(request.targetLabel), mountPath=\(mountPath)",
            shouldAdvancePercent: false
        )
    }

    private func runWindowsUnmountCommand(stage: WorkflowStage, arguments: [String]) throws -> (success: Bool, exitCode: Int32, isBusyFailure: Bool, lastLine: String?) {
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
                if isWindowsUnmountBusyLine(line) {
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
            if isWindowsUnmountBusyLine(line) {
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

    private func runWindowsFormatCommand(stage: WorkflowStage, wholeDisk: String) throws {
        _ = try runSimpleCommand(
            executable: "/usr/sbin/diskutil",
            arguments: ["eraseDisk", "MS-DOS", request.targetLabel, "MBRFormat", "/dev/\(wholeDisk)"],
            stageKey: stage.key,
            stageTitleKey: stage.titleKey,
            statusKey: stage.statusKey
        )
    }

    private func waitWindowsUnmountRetryDelay(seconds: Int) throws {
        guard seconds > 0 else { return }
        for _ in 0..<(seconds * 10) {
            try throwIfCancelled()
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func waitForWindowsTargetVolumeMountPath(
        stage: WorkflowStage,
        wholeDisk: String,
        preferredVolumeName: String
    ) throws -> String {
        let preferredMountPath = "/Volumes/\(preferredVolumeName)"

        for _ in 0..<70 {
            if let resolvedMountPath = resolveMountedVolumePathForWholeDisk(wholeDisk),
               isExistingDirectory(atPath: resolvedMountPath) {
                return resolvedMountPath
            }

            if isExistingDirectory(atPath: preferredMountPath),
               isMountPathBackedByWholeDisk(preferredMountPath, wholeDisk: wholeDisk) {
                return preferredMountPath
            }
            try throwIfCancelled()
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw HelperExecutionError.failed(
            stage: stage.key,
            exitCode: -1,
            description: "Nie znaleziono zamontowanego woluminu USB po formatowaniu dla urządzenia \(wholeDisk)."
        )
    }

    func resolveMountedVolumePathForWholeDisk(_ wholeDisk: String) -> String? {
        guard let info = diskutilPlist(arguments: ["list", "-plist", "/dev/\(wholeDisk)"]),
              let partitions = info["Partitions"] as? [[String: Any]] else {
            return nil
        }

        for partition in partitions {
            if let mountPoint = partition["MountPoint"] as? String,
               !mountPoint.isEmpty {
                return mountPoint
            }
        }
        return nil
    }

    private func isMountPathBackedByWholeDisk(_ mountPath: String, wholeDisk: String) -> Bool {
        guard let info = diskutilPlist(arguments: ["info", "-plist", mountPath]),
              let deviceIdentifier = info["DeviceIdentifier"] as? String else {
            return false
        }
        return deviceIdentifier.hasPrefix(wholeDisk)
    }

    private func diskutilPlist(arguments: [String]) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        process.standardOutput = Pipe()
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

        let data = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }

        return dictionary
    }

    private func isExistingDirectory(atPath path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isWindowsUnmountBusyLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("at least one volume could not be unmounted")
            || lowered.contains("unmount was dissented by pid")
            || lowered.contains("resource busy")
            || lowered.contains("device busy")
    }
}
