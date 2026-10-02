import Foundation
import AppKit

extension LinuxDownloadFlowModel {
    func runWorkflow(for entry: LinuxImageEntry, destinationDirectoryURL: URL) async {
        let sleepBlockToken = SystemSleepBlocker.shared.begin(
            reason: "Linux image download",
            loggingStage: .downloader,
            loggingWorkflow: .linux
        )
        defer { SystemSleepBlocker.shared.end(sleepBlockToken) }

        workflowState = .running
        AppLogging.info(
            "Download started: \(entry.title) [\(entry.architecture.rawValue)] from \(entry.downloadURL.absoluteString); SHA-256 source \(entry.checksumSourceURL.absoluteString); destination folder \(destinationDirectoryURL.path).",
            stage: .downloader, workflow: .linux
        )

        do {
            let expectedBytes = try await runConnectionCheck(
                for: entry,
                destinationDirectoryURL: destinationDirectoryURL
            )
            let downloadedFileURL = try await runImageDownload(for: entry, expectedBytes: expectedBytes)
            try await runChecksumVerification(of: downloadedFileURL, entry: entry)
            try runFinalization(
                of: downloadedFileURL,
                entry: entry,
                destinationDirectoryURL: destinationDirectoryURL
            )

            updateSummaryMetrics()
            isFinished = true
            workflowState = .completed
            playCompletionSound(success: true)
            AppLogging.info(
                "Download completed successfully. File: \(finalImageURL?.path ?? "-").",
                stage: .downloader, workflow: .linux
            )
        } catch let error as LinuxDownloadInsufficientSpace {
            AppLogging.error(
                "Insufficient disk space. Required=\(MacOSDownloadDiskSpaceDiagnostics.describe(error.requiredBytes)), available=\(MacOSDownloadDiskSpaceDiagnostics.describe(error.availableBytes)).",
                stage: .downloader, workflow: .linux
            )
            removeSessionDirectory()
            workflowState = .idle
            pendingDiskSpaceAlert = DiskSpaceAlertContext(
                requiredMinimumText: DownloadManifestItem.formatBytes(error.requiredBytes),
                availableText: DownloadManifestItem.formatBytes(error.availableBytes)
            )
        } catch is CancellationError {
            handleCancellation()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            handleCancellation()
        } catch {
            removeSessionDirectory()
            AppLogging.error(
                "Download failed at stage \(currentStage): \(error.localizedDescription)",
                stage: .downloader, workflow: .linux
            )
            updateSummaryMetrics()
            failureMessage = (error as? LinuxDownloadFailureReason)?.errorDescription
                ?? LinuxDownloadFailureReason.downloadFailed(error.localizedDescription).errorDescription
            isFinished = true
            workflowState = .failed
            playCompletionSound(success: false)
        }
    }

    private func handleCancellation() {
        removeSessionDirectory()
        workflowState = .cancelled
        AppLogging.info("Download cancelled.", stage: .downloader, workflow: .linux)
    }

    // MARK: - Connection and preflight

    private func runConnectionCheck(
        for entry: LinuxImageEntry,
        destinationDirectoryURL: URL
    ) async throws -> Int64 {
        currentStage = .connection
        connectionStatusText = String(
            format: String(localized: "downloader.linux.connection.connecting"),
            entry.downloadURL.host ?? entry.downloadURL.absoluteString
        )

        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: destinationDirectoryURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue,
            FileManager.default.isWritableFile(atPath: destinationDirectoryURL.path)
        else {
            throw LinuxDownloadFailureReason.destinationUnavailable
        }

        let expectedBytes: Int64
        if let sizeBytes = entry.sizeBytes {
            expectedBytes = sizeBytes
        } else {
            let sources = LinuxDiscoverySources(session: LinuxDiscoverySources.makeSession())
            guard let probedSize = await sources.probeSize(of: entry.downloadURL) else {
                throw LinuxDownloadFailureReason.downloadFailed(
                    String(localized: "downloader.linux.error.server_unreachable")
                )
            }
            expectedBytes = probedSize
        }
        try Task.checkCancellation()

        connectionStatusText = String(localized: "downloader.linux.connection.checking_space")
        try verifyDiskCapacity(
            expectedBytes: expectedBytes,
            destinationDirectoryURL: destinationDirectoryURL
        )
        try prepareSessionDirectory()

        completedStages.insert(.connection)
        return expectedBytes
    }

    /// The image is downloaded to the system temporary folder and then moved, so both volumes need room for it.
    private func verifyDiskCapacity(expectedBytes: Int64, destinationDirectoryURL: URL) throws {
        let requiredBytes = Int64((Double(expectedBytes) * 1.05).rounded(.up))
        let temporaryURL = FileManager.default.temporaryDirectory
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeIdentifierKey]
        let temporaryValues = try temporaryURL.resourceValues(forKeys: keys)
        let destinationValues = try destinationDirectoryURL.resourceValues(forKeys: keys)

        let checks: [(URL, URLResourceValues, Int64)]
        if let temporaryVolume = temporaryValues.volumeIdentifier as? NSObject,
           let destinationVolume = destinationValues.volumeIdentifier as? NSObject,
           temporaryVolume.isEqual(destinationVolume) {
            checks = [(temporaryURL, temporaryValues, requiredBytes)]
        } else {
            checks = [
                (temporaryURL, temporaryValues, requiredBytes),
                (destinationDirectoryURL, destinationValues, requiredBytes)
            ]
        }

        for (url, values, required) in checks {
            let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            AppLogging.info(
                "Disk space preflight [\(url.path)]: required=\(MacOSDownloadDiskSpaceDiagnostics.describe(required)), available=\(MacOSDownloadDiskSpaceDiagnostics.describe(available)), result=\(MacOSDownloadDiskSpaceDiagnostics.status(requiredBytes: required, availableBytes: available)).",
                stage: .downloader, workflow: .linux
            )
            guard available >= required else {
                throw LinuxDownloadInsufficientSpace(requiredBytes: required, availableBytes: available)
            }
        }
    }

    private func prepareSessionDirectory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macUSB_temp", isDirectory: true)
            .appendingPathComponent("linux_downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            throw LinuxDownloadFailureReason.downloadFailed(error.localizedDescription)
        }
        activeSessionRootURL = rootURL
    }

    // MARK: - Download

    private func runImageDownload(for entry: LinuxImageEntry, expectedBytes: Int64) async throws -> URL {
        currentStage = .downloading
        downloadProgress = 0
        guard let sessionRootURL = activeSessionRootURL else {
            throw LinuxDownloadFailureReason.downloadFailed(entry.fileName)
        }
        let destinationURL = sessionRootURL.appendingPathComponent(entry.fileName)

        let maxAttempts = 3
        var attempt = 1
        while true {
            do {
                let bytes = try await downloadImage(
                    from: entry.downloadURL,
                    fileName: entry.fileName,
                    to: destinationURL,
                    expectedBytes: expectedBytes
                )
                totalDownloadedBytes = bytes
                break
            } catch let error as URLError where error.code != .cancelled && attempt < maxAttempts {
                AppLogging.error(
                    "Download attempt \(attempt)/\(maxAttempts) failed (\(error.code.rawValue)): \(error.localizedDescription). Retrying.",
                    stage: .downloader, workflow: .linux
                )
                attempt += 1
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch let error as URLError where error.code != .cancelled {
                throw LinuxDownloadFailureReason.downloadFailed(error.localizedDescription)
            } catch DownloadFailureReason.downloadFailed(let details) {
                throw LinuxDownloadFailureReason.downloadFailed(details)
            }
        }

        downloadProgress = 1
        completedStages.insert(.downloading)
        return destinationURL
    }

    private func downloadImage(
        from url: URL,
        fileName: String,
        to destinationURL: URL,
        expectedBytes: Int64
    ) async throws -> Int64 {
        lastSpeedSampleDate = Date()
        lastSpeedSampleBytes = 0

        let delegate = FileDownloadTaskDelegate(
            expectedBytesFallback: expectedBytes,
            destinationURL: destinationURL,
            fileName: fileName
        ) { [weak self] received, expected in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let total = max(expected, expectedBytes, 1)
                self.downloadTransferredText = self.formatTransferStatus(downloadedBytes: received, totalBytes: total)
                self.downloadProgress = min(1, Double(received) / Double(total))

                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastSpeedSampleDate)
                if elapsed >= 2 {
                    let speedMBps = (Double(max(0, received - self.lastSpeedSampleBytes)) / 1_000_000) / elapsed
                    self.downloadSpeedText = "\(self.formatDecimal(speedMBps, fractionDigits: 1)) MB/s"
                    self.speedSamplesMBps.append(speedMBps)
                    self.lastSpeedSampleDate = now
                    self.lastSpeedSampleBytes = received
                }
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 86_400
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        activeDownloadSession = session
        activeDownloadTaskDelegate = delegate

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let task = session.downloadTask(with: request)
        activeDownloadTask = task

        defer {
            activeDownloadTask = nil
            activeDownloadSession?.finishTasksAndInvalidate()
            activeDownloadSession = nil
            activeDownloadTaskDelegate = nil
        }

        return try await withTaskCancellationHandler {
            try await delegate.run(task: task)
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Verification

    private func runChecksumVerification(of fileURL: URL, entry: LinuxImageEntry) async throws {
        currentStage = .verifying
        verifyProgress = 0

        let actualSHA256: String
        do {
            actualSHA256 = try await LinuxDownloadChecksumVerifier.sha256(of: fileURL) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.verifyProgress = fraction
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LinuxDownloadFailureReason.verificationFailed(error.localizedDescription)
        }

        AppLogging.info(
            "SHA-256 verification for \(entry.fileName): expected=\(entry.expectedSHA256), computed=\(actualSHA256).",
            stage: .downloader, workflow: .linux
        )
        guard actualSHA256 == entry.expectedSHA256.lowercased() else {
            throw LinuxDownloadFailureReason.checksumMismatch
        }

        verifyProgress = 1
        completedStages.insert(.verifying)
    }

    // MARK: - Finalization

    private func runFinalization(
        of fileURL: URL,
        entry: LinuxImageEntry,
        destinationDirectoryURL: URL
    ) throws {
        currentStage = .finalizing
        finalizeStatusText = String(localized: "downloader.linux.finalizing.moving")

        let targetURL = collisionFreeURL(for: entry.fileName, in: destinationDirectoryURL)
        do {
            try FileManager.default.moveItem(at: fileURL, to: targetURL)
        } catch {
            throw LinuxDownloadFailureReason.moveFailed(error.localizedDescription)
        }
        finalImageURL = targetURL
        removeSessionDirectory()
        completedStages.insert(.finalizing)
    }

    private func collisionFreeURL(for fileName: String, in directoryURL: URL) -> URL {
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        var candidate = directoryURL.appendingPathComponent(fileName)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appendingPathComponent("\(baseName) (\(suffix)).\(pathExtension)")
            suffix += 1
        }
        return candidate
    }

    // MARK: - Summary

    private func updateSummaryMetrics() {
        summaryTotalDownloadedText = DownloadManifestItem.formatBytes(totalDownloadedBytes)

        let averageSpeed: Double
        if let processStartedAt, totalDownloadedBytes > 0 {
            let elapsed = max(Date().timeIntervalSince(processStartedAt), 1)
            averageSpeed = (Double(totalDownloadedBytes) / 1_000_000) / elapsed
        } else {
            averageSpeed = speedSamplesMBps.isEmpty ? 0 : speedSamplesMBps.reduce(0, +) / Double(speedSamplesMBps.count)
        }
        summaryAverageSpeedText = "\(formatDecimal(averageSpeed, fractionDigits: 1)) MB/s"

        let totalSeconds = Int((processStartedAt.map { Date().timeIntervalSince($0) } ?? 0).rounded())
        summaryDurationText = String(
            format: String(localized: "%02dm %02ds"),
            totalSeconds / 60,
            totalSeconds % 60
        )
    }

    func formatTransferStatus(downloadedBytes: Int64, totalBytes: Int64) -> String {
        if totalBytes < 1_000_000_000 {
            let downloadedMB = Double(downloadedBytes) / 1_000_000
            let totalMB = Double(totalBytes) / 1_000_000
            return "\(formatDecimal(downloadedMB, fractionDigits: 1))MB/\(formatDecimal(totalMB, fractionDigits: 1))MB"
        }
        let downloadedGB = Double(downloadedBytes) / 1_000_000_000
        let totalGB = Double(totalBytes) / 1_000_000_000
        return "\(formatDecimal(downloadedGB, fractionDigits: 1))GB/\(formatDecimal(totalGB, fractionDigits: 1))GB"
    }

    func formatDecimal(_ value: Double, fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func playCompletionSound(success: Bool) {
        guard success else {
            NSSound(named: NSSound.Name("Basso"))?.play()
            return
        }
        let bundledSoundURL =
            Bundle.main.url(forResource: "burn_complete", withExtension: "aif", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: "burn_complete", withExtension: "aif")
        if let bundledSoundURL, let sound = NSSound(contentsOf: bundledSoundURL, byReference: false) {
            sound.play()
        } else {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }
}
