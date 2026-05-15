import Foundation

extension HelperWorkflowExecutor {
    private static let windowsFAT32LimitBytes: Int64 = 4_294_967_295

    func runWindowsPrepareSourceStage(_ stage: WorkflowStage) throws {
        guard fileManager.fileExists(atPath: request.sourceAppPath) else {
            throw HelperExecutionError.invalidRequest("Nie znaleziono źródłowego pliku ISO Windows.")
        }

        let mountedSourcePath = try prepareWindowsSourceMountPath(stage: stage)
        windowsActiveSourceMountPath = mountedSourcePath

        let sourceURL = URL(fileURLWithPath: mountedSourcePath)
        let sourcesDirectory = resolveWindowsSourcesDirectory(in: sourceURL)
        guard fileManager.fileExists(atPath: sourcesDirectory.path) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Źródłowy obraz nie wygląda jak instalator Windows: brak katalogu sources/Sources."
            )
        }
        let sourceUEFIStatus = evaluateWindowsUEFIStatus(in: sourceURL)

        guard sourceUEFIStatus.hasCompatibleEFI else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "W obrazie źródłowym nie znaleziono wymaganych markerów UEFI (katalog EFI oraz co najmniej jeden plik: bootmgr.efi, EFI/Microsoft/Boot/cdboot.efi, EFI/BOOT/BOOTX64.EFI, EFI/BOOT/BOOTAA64.EFI)."
            )
        }

        let installWimInfo = resolveWindowsInstallWimInfo(in: sourcesDirectory)
        let installEsdInfo = resolveWindowsInstallEsdInfo(in: sourcesDirectory)
        windowsInstallWimPath = installWimInfo?.path
        windowsInstallWimRelativePath = installWimInfo?.relativePath
        windowsInstallWimSizeBytes = installWimInfo?.size
        windowsHasInstallESD = installEsdInfo != nil

        let oversizedNonWimFiles = try findWindowsOversizedFiles(
            in: sourceURL,
            excludedFilePath: installWimInfo?.path
        )

        if !oversizedNonWimFiles.isEmpty {
            let listed = oversizedNonWimFiles.prefix(5).joined(separator: ", ")
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Źródłowy obraz zawiera pliki większe niż limit FAT32 (inne niż install.wim): \(listed)."
            )
        }

        let shouldSplitWim = (installWimInfo?.size ?? 0) > Self.windowsFAT32LimitBytes
        windowsShouldSplitWim = shouldSplitWim
        windowsCopyStageTotalBytes = try computeWindowsCopyPayloadBytes(
            in: sourceURL,
            excludedFilePath: shouldSplitWim ? installWimInfo?.path : nil
        )

        if shouldSplitWim {
            guard let executable = resolveExecutablePath(named: "wimlib-imagex") else {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Plik install.wim przekracza limit FAT32, ale nie znaleziono polecenia wimlib-imagex. Zainstaluj wimlib i spróbuj ponownie."
                )
            }
            windowsWimlibExecutablePath = executable
        }

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows source prepared: mount=\(mountedSourcePath), splitWIM=\(shouldSplitWim ? "yes" : "no"), hasESD=\(windowsHasInstallESD ? "yes" : "no"), copyBytes=\(windowsCopyStageTotalBytes ?? -1)",
            shouldAdvancePercent: false
        )
    }

    func prepareWindowsSourceMountPath(stage: WorkflowStage) throws -> String {
        let requestedMountPath = request.windowsMountedSourcePath?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let resolvedMountPath = resolveMountedPathForSourceImage(sourceImagePath: request.sourceAppPath),
           isWindowsSourceMountReusable(resolvedMountPath) {
            windowsMountedByHelper = false
            windowsMountedImageDevice = nil
            let reusedFromRequest = requestedMountPath.map { normalizedPath($0) == normalizedPath(resolvedMountPath) } ?? false
            let reuseLog: String
            if reusedFromRequest {
                reuseLog = "Windows source mount reused from analysis: \(resolvedMountPath)"
            } else {
                reuseLog = "Windows source mount reused after source-image verification (requestMount=\(requestedMountPath ?? "brak"), verifiedMount=\(resolvedMountPath))."
            }
            emitProgress(
                stageKey: stage.key,
                titleKey: stage.titleKey,
                percent: latestPercent,
                statusKey: stage.statusKey,
                logLine: reuseLog,
                shouldAdvancePercent: false
            )
            return resolvedMountPath
        }

        if let requestedMountPath, !requestedMountPath.isEmpty {
            emitProgress(
                stageKey: stage.key,
                titleKey: stage.titleKey,
                percent: latestPercent,
                statusKey: stage.statusKey,
                logLine: "Windows source mount from analysis ignored: does not match selected ISO source (\(requestedMountPath)).",
                shouldAdvancePercent: false
            )
        }

        let attachResult = try attachWindowsSourceISO(stage: stage)
        windowsMountedByHelper = true
        windowsMountedImageDevice = attachResult.device
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows source mounted as hidden volume: \(attachResult.mountPath)",
            shouldAdvancePercent: false
        )
        return attachResult.mountPath
    }

    func attachWindowsSourceISO(stage: WorkflowStage) throws -> (device: String, mountPath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-nobrowse", "-readonly", request.sourceAppPath]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się uruchomić hdiutil attach: \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()

        let stdoutData = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let stderrData = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: process.terminationStatus,
                description: stderrText.isEmpty ? "Polecenie hdiutil attach zakończyło się błędem." : stderrText
            )
        }

        guard let stdout = String(data: stdoutData, encoding: .utf8) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się odczytać wyniku hdiutil attach."
            )
        }

        let lines = stdout
            .split(separator: "\n")
            .map(String.init)
        for line in lines {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            let device = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let mountPath = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            if device.hasPrefix("/dev/") && mountPath.hasPrefix("/Volumes/") {
                return (device: device, mountPath: mountPath)
            }
        }

        throw HelperExecutionError.failed(
            stage: stage.key,
            exitCode: -1,
            description: "Nie udało się ustalić punktu montowania ISO Windows."
        )
    }

    private func resolveMountedPathForSourceImage(sourceImagePath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
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

        let outputData = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        guard let plist = try? PropertyListSerialization.propertyList(from: outputData, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return nil
        }

        let normalizedSourcePath = normalizedPath(sourceImagePath)
        for image in images {
            guard let imagePath = image["image-path"] as? String,
                  normalizedPath(imagePath) == normalizedSourcePath else {
                continue
            }

            guard let entities = image["system-entities"] as? [[String: Any]],
                  let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
                continue
            }

            return mountPoint
        }

        return nil
    }

    private func isWindowsSourceMountReusable(_ mountPath: String) -> Bool {
        guard fileManager.fileExists(atPath: mountPath) else { return false }
        let mountURL = URL(fileURLWithPath: mountPath)
        let lowerSources = mountURL.appendingPathComponent("sources").path
        let upperSources = mountURL.appendingPathComponent("Sources").path
        return fileManager.fileExists(atPath: lowerSources) || fileManager.fileExists(atPath: upperSources)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func resolveWindowsSourcesDirectory(in mountURL: URL) -> URL {
        let lower = mountURL.appendingPathComponent("sources")
        if fileManager.fileExists(atPath: lower.path) {
            return lower
        }

        let upper = mountURL.appendingPathComponent("Sources")
        return upper
    }

    private func resolveWindowsInstallWimInfo(in sourcesDirectory: URL) -> (path: String, relativePath: String, size: Int64)? {
        let candidates = [
            sourcesDirectory.appendingPathComponent("install.wim"),
            sourcesDirectory.appendingPathComponent("INSTALL.WIM")
        ]

        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.path),
                  let size = fileSize(at: candidate.path),
                  let mountPath = windowsActiveSourceMountPath,
                  candidate.path.hasPrefix(mountPath + "/") else {
                continue
            }

            let relative = String(candidate.path.dropFirst((mountPath + "/").count))
            return (candidate.path, relative, size)
        }

        return nil
    }

    private func resolveWindowsInstallEsdInfo(in sourcesDirectory: URL) -> String? {
        let candidates = [
            sourcesDirectory.appendingPathComponent("install.esd"),
            sourcesDirectory.appendingPathComponent("INSTALL.ESD")
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate.path
        }

        return nil
    }

    private func findWindowsOversizedFiles(in sourceURL: URL, excludedFilePath: String?) throws -> [String] {
        let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )

        var oversized: [String] = []
        while let next = enumerator?.nextObject() as? URL {
            let values = try next.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }

            guard Int64(fileSize) > Self.windowsFAT32LimitBytes else {
                continue
            }

            if let excludedFilePath, next.path == excludedFilePath {
                continue
            }

            oversized.append(next.path)
        }

        return oversized
    }

    private func computeWindowsCopyPayloadBytes(in sourceURL: URL, excludedFilePath: String?) throws -> Int64 {
        let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )

        var totalBytes: Int64 = 0
        while let next = enumerator?.nextObject() as? URL {
            guard let values = try? next.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }

            if let excludedFilePath, next.path == excludedFilePath {
                continue
            }

            totalBytes += Int64(fileSize)
        }

        return totalBytes
    }

    private func resolveExecutablePath(named executable: String) -> String? {
        let fm = fileManager
        let fixedSearchRoots = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        for root in fixedSearchRoots {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent(executable).path
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"], !pathEnv.isEmpty {
            for root in pathEnv.split(separator: ":").map(String.init) {
                let candidate = URL(fileURLWithPath: root).appendingPathComponent(executable).path
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executable]
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

        let outputData = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        guard let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        return output
    }

    private func fileSize(at path: String) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
    }
}
