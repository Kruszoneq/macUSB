import Foundation

extension HelperWorkflowExecutor {
    func buildWindowsWorkflowStages(using _: PreparedWorkflowContext) throws -> [WorkflowStage] {
        var stages: [WorkflowStage] = [
            WorkflowStage(
                key: "windows_prepare_source",
                titleKey: HelperWorkflowLocalizationKeys.windowsPrepareSourceTitle,
                statusKey: HelperWorkflowLocalizationKeys.windowsPrepareSourceStatus,
                startPercent: 10,
                endPercent: 30,
                executable: "/usr/bin/true",
                arguments: [],
                parseToolPercent: false
            ),
            WorkflowStage(
                key: "windows_prepare_target",
                titleKey: HelperWorkflowLocalizationKeys.windowsPrepareTargetTitle,
                statusKey: HelperWorkflowLocalizationKeys.windowsPrepareTargetStatus,
                startPercent: 30,
                endPercent: 40,
                executable: "/usr/bin/true",
                arguments: [],
                parseToolPercent: false
            ),
            WorkflowStage(
                key: "windows_create_media",
                titleKey: HelperWorkflowLocalizationKeys.windowsCreateMediaTitle,
                statusKey: HelperWorkflowLocalizationKeys.windowsCreateMediaStatus,
                startPercent: 40,
                endPercent: 80,
                executable: "/usr/bin/true",
                arguments: [],
                parseToolPercent: true
            )
        ]

        stages.append(
            WorkflowStage(
                key: "windows_split_wim",
                titleKey: HelperWorkflowLocalizationKeys.windowsSplitWimTitle,
                statusKey: HelperWorkflowLocalizationKeys.windowsSplitWimStatus,
                startPercent: 80,
                endPercent: 95,
                executable: "/usr/bin/true",
                arguments: [],
                parseToolPercent: true
            )
        )

        stages.append(
            WorkflowStage(
                key: "windows_verify_media",
                titleKey: HelperWorkflowLocalizationKeys.windowsVerifyMediaTitle,
                statusKey: HelperWorkflowLocalizationKeys.windowsVerifyMediaStatus,
                startPercent: 95,
                endPercent: 98,
                executable: "/usr/bin/true",
                arguments: [],
                parseToolPercent: false
            )
        )

        return stages
    }

    func shouldSkipWindowsStage(_ stage: WorkflowStage) -> Bool {
        guard request.workflowKind == .windows else { return false }
        return stage.key == "windows_split_wim" && !windowsShouldSplitWim
    }

    func runWindowsCreateMediaStage(_ stage: WorkflowStage) throws {
        let sourceMountPath = try ensureWindowsSourceMountPathForCopy(stage: stage)
        let targetVolumePath = try ensureWindowsTargetMountPathForCopy(stage: stage)
        let sourceCanonicalPath = URL(fileURLWithPath: sourceMountPath).resolvingSymlinksInPath().path
        let targetCanonicalPath = URL(fileURLWithPath: targetVolumePath).resolvingSymlinksInPath().path

        if sourceCanonicalPath == targetCanonicalPath {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nieprawidłowa konfiguracja kopiowania: źródło i cel wskazują na ten sam katalog (\(sourceCanonicalPath))."
            )
        }

        guard isWindowsSourceDirectoryStructureValid(sourceCanonicalPath) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Źródło kopiowania nie jest poprawnym katalogiem obrazu Windows: \(sourceCanonicalPath)."
            )
        }

        guard isWindowsMountedDirectoryUsable(targetCanonicalPath) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Katalog docelowy nośnika USB nie istnieje lub nie jest katalogiem: \(targetCanonicalPath)."
            )
        }

        guard let sourceDevice = deviceIdentifierForMountPath(sourceCanonicalPath),
              let targetDevice = deviceIdentifierForMountPath(targetCanonicalPath) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się ustalić identyfikatorów urządzeń dla kopiowania (source=\(sourceCanonicalPath), target=\(targetCanonicalPath))."
            )
        }

        let sourceWholeDisk = try extractWholeDiskName(from: sourceDevice)
        let targetWholeDisk = try extractWholeDiskName(from: targetDevice)
        if sourceWholeDisk == targetWholeDisk {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nośnik źródłowy i docelowy wskazują na to samo urządzenie (\(sourceWholeDisk)). Wybierz inny dysk docelowy USB."
            )
        }

        let rsyncPlan = resolveRsyncExecutionPlan()
        windowsRsyncProgressMode = rsyncPlan.mode
        windowsLegacyRsyncCurrentFilePath = nil
        windowsLegacyRsyncCurrentFileSizeBytes = 0
        windowsLegacyRsyncCompletedBytes = 0
        windowsLegacyRsyncToCheckUsesProcessedCount = nil
        var createArguments = rsyncPlan.arguments

        if windowsShouldSplitWim, let relativeWimPath = windowsInstallWimRelativePath {
            createArguments.append("--exclude=/\(relativeWimPath)")
        }

        createArguments.append("\(sourceCanonicalPath)/")
        createArguments.append("\(targetCanonicalPath)/")

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows copy command: \(rsyncPlan.executable) \(createArguments.joined(separator: " ")) [sourceDevice=\(sourceDevice), targetDevice=\(targetDevice), mode=\(rsyncPlan.mode)]",
            shouldAdvancePercent: false
        )

        try runWindowsStreamingStageCommand(
            stage: stage,
            executable: rsyncPlan.executable,
            arguments: createArguments
        )
    }

    func runWindowsSplitWimStage(_ stage: WorkflowStage) throws {
        guard windowsShouldSplitWim else { return }
        guard let installWimPath = windowsInstallWimPath,
              let wimlibPath = windowsWimlibExecutablePath else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Brak danych wymaganych do podziału install.wim."
            )
        }

        let targetVolumePath = windowsPreparedTargetVolumePath ?? "/Volumes/\(request.targetLabel)"
        let relativeWimPath = windowsInstallWimRelativePath ?? "sources/install.wim"
        let sourcesSubdirectory = (relativeWimPath as NSString).deletingLastPathComponent
        let targetSplitPath = URL(fileURLWithPath: targetVolumePath)
            .appendingPathComponent(sourcesSubdirectory)
            .appendingPathComponent("install.swm")
            .path

        try runWindowsStreamingStageCommand(
            stage: stage,
            executable: wimlibPath,
            arguments: ["split", installWimPath, targetSplitPath, "3800"]
        )
    }

    private func ensureWindowsSourceMountPathForCopy(stage: WorkflowStage) throws -> String {
        if let currentPath = windowsActiveSourceMountPath,
           isWindowsMountedDirectoryUsable(currentPath) {
            return currentPath
        }

        let attachResult = try attachWindowsSourceISO(stage: stage)
        windowsMountedByHelper = true
        windowsMountedImageDevice = attachResult.device
        windowsActiveSourceMountPath = attachResult.mountPath

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows source remounted before copy: \(attachResult.mountPath)",
            shouldAdvancePercent: false
        )

        return attachResult.mountPath
    }

    private func ensureWindowsTargetMountPathForCopy(stage: WorkflowStage) throws -> String {
        if let currentPath = windowsPreparedTargetVolumePath,
           isWindowsMountedDirectoryUsable(currentPath) {
            return currentPath
        }

        let wholeDisk = try extractWholeDiskName(from: request.targetBSDName)
        guard let remountedPath = resolveMountedVolumePathForWholeDisk(wholeDisk),
              isWindowsMountedDirectoryUsable(remountedPath) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie znaleziono zamontowanego woluminu docelowego USB przed kopiowaniem."
            )
        }

        windowsPreparedTargetVolumePath = remountedPath
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows target path refreshed before copy: \(remountedPath)",
            shouldAdvancePercent: false
        )
        return remountedPath
    }

    private func isWindowsMountedDirectoryUsable(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isWindowsSourceDirectoryStructureValid(_ sourcePath: String) -> Bool {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let sourcesLower = sourceURL.appendingPathComponent("sources").path
        let sourcesUpper = sourceURL.appendingPathComponent("Sources").path
        return isWindowsMountedDirectoryUsable(sourcePath)
            && (fileManager.fileExists(atPath: sourcesLower) || fileManager.fileExists(atPath: sourcesUpper))
    }

    private func deviceIdentifierForMountPath(_ mountPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", mountPath]
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
              let dictionary = plist as? [String: Any],
              let deviceIdentifier = dictionary["DeviceIdentifier"] as? String,
              !deviceIdentifier.isEmpty else {
            return nil
        }

        return deviceIdentifier
    }

    private func resolveRsyncExecutionPlan() -> (executable: String, arguments: [String], mode: String) {
        let candidates = [
            "/opt/homebrew/bin/rsync",
            "/usr/local/bin/rsync",
            "/opt/local/bin/rsync",
            "/usr/bin/rsync"
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            if supportsRsyncProgress2(executable: candidate) {
                return (candidate, ["-a", "--info=progress2,name0"], "progress2")
            }
            return (candidate, ["-a", "-h", "--progress"], "legacy-progress")
        }

        return ("/usr/bin/rsync", ["-a", "-h", "--progress"], "legacy-progress-fallback")
    }

    private func supportsRsyncProgress2(executable: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return false
        }

        let data = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        guard let output = String(data: data, encoding: .utf8)?.lowercased() else {
            return false
        }

        // macOS ships ancient rsync 2.6.9 (openrsync-compatible usage) without --info=progress2.
        if output.contains("version 2.6.9") || output.contains("protocol version 29") {
            return false
        }

        return true
    }

    private func runWindowsStreamingStageCommand(
        stage: WorkflowStage,
        executable: String,
        arguments: [String]
    ) throws {
        let process = Process()
        if let requesterUID = request.requesterUID, requesterUID > 0 {
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["asuser", "\(requesterUID)", executable] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        }
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        process.environment = env

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
                stage: stage.key,
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
            var description = "Polecenie \(executable) zakończyło się błędem (kod \(process.terminationStatus))."
            if let lastLine = lastStageOutputLine {
                description += " Ostatni komunikat: \(lastLine)"
            }
            if !arguments.isEmpty {
                description += " Args: \(arguments.joined(separator: " "))"
            }
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: process.terminationStatus,
                description: description
            )
        }
    }
}
