import Foundation

extension MontereyDownloadFlowModel {
    func runFileDownloads(manifest: DownloadManifest) async throws {
        currentStage = .downloading
        downloadCurrentIndex = 0
        downloadTotal = manifest.items.count
        downloadProgress = 0
        totalDownloadedBytes = 0
        downloadSpeedText = "0.0 MB/s"
        downloadTransferredText = "0.0MB/0.0MB"

        let totalExpectedBytes = max(manifest.totalExpectedBytes, 1)
        var downloadedOverallBytes: Int64 = 0

        for (index, item) in manifest.items.enumerated() {
            try Task.checkCancellation()
            guard let payloadURL = activeSessionPayloadURL else {
                throw DownloadFailureReason.sessionInitializationFailed(String(localized: "Brak katalogu payload sesji"))
            }

            downloadCurrentIndex = index + 1
            downloadFileName = String(
                format: String(localized: "Pobieranie pliku %@..."),
                item.name
            )

            let itemDestinationURL = payloadURL.appendingPathComponent(
                destinationFileName(for: item, index: index, manifest: manifest)
            )
            let startedAt = Date()
            var lastSampleDate = startedAt
            var lastSampleBytes: Int64 = 0

            let bytesDownloaded = try await downloadItemWithRetry(
                item,
                destinationURL: itemDestinationURL,
                maxAttempts: 3
            ) { [weak self] receivedBytes, expectedBytes in
                guard let self else { return }
                let fileExpected = max(expectedBytes, item.expectedSizeBytes, 1)
                let now = Date()

                self.downloadTransferredText = self.formatTransferStatus(
                    downloadedBytes: receivedBytes,
                    totalBytes: fileExpected
                )

                let combinedReceived = downloadedOverallBytes + receivedBytes
                self.downloadProgress = min(
                    1.0,
                    Double(combinedReceived) / Double(totalExpectedBytes)
                )

                let elapsed = now.timeIntervalSince(lastSampleDate)
                if elapsed >= 2 {
                    let deltaBytes = max(0, receivedBytes - lastSampleBytes)
                    let speedMBps = (Double(deltaBytes) / 1_000_000) / elapsed
                    self.downloadSpeedText = "\(self.formatDecimal(speedMBps, fractionDigits: 1)) MB/s"
                    self.speedSamplesMBps.append(speedMBps)
                    lastSampleDate = now
                    lastSampleBytes = receivedBytes
                }
            }

            downloadedOverallBytes += bytesDownloaded
            downloadedFileURLsByItemID[item.id] = itemDestinationURL
        }

        totalDownloadedBytes = downloadedOverallBytes
        downloadProgress = 1.0
        completedStages.insert(.downloading)
    }

    func downloadItem(
        _ item: DownloadManifestItem,
        to destinationURL: URL,
        progress: @escaping @MainActor (_ receivedBytes: Int64, _ expectedBytes: Int64) -> Void
    ) async throws -> Int64 {
        let delegate = FileDownloadTaskDelegate(
            expectedBytesFallback: item.expectedSizeBytes,
            destinationURL: destinationURL,
            fileName: item.name
        ) { received, expected in
            Task { @MainActor in
                progress(received, expected)
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 86_400
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        activeDownloadSession = session
        activeDownloadTaskDelegate = delegate

        var request = URLRequest(url: item.url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let task = session.downloadTask(with: request)
        activeDownloadTask = task

        let fileSize: Int64 = try await withTaskCancellationHandler(operation: {
            try await delegate.run(task: task)
        }, onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.activeDownloadTask?.cancel()
                self?.activeDownloadSession?.invalidateAndCancel()
            }
        })

        activeDownloadTask = nil
        activeDownloadSession?.invalidateAndCancel()
        activeDownloadSession = nil
        activeDownloadTaskDelegate = nil

        return max(0, fileSize)
    }
}

final class FileDownloadTaskDelegate: NSObject, URLSessionDownloadDelegate {
    private let expectedBytesFallback: Int64
    private let destinationURL: URL
    private let fileName: String
    private let progressHandler: (_ receivedBytes: Int64, _ expectedBytes: Int64) -> Void
    private var continuation: CheckedContinuation<Int64, Error>?

    init(
        expectedBytesFallback: Int64,
        destinationURL: URL,
        fileName: String,
        progressHandler: @escaping (_ receivedBytes: Int64, _ expectedBytes: Int64) -> Void
    ) {
        self.expectedBytesFallback = expectedBytesFallback
        self.destinationURL = destinationURL
        self.fileName = fileName
        self.progressHandler = progressHandler
    }

    func run(task: URLSessionDownloadTask) async throws -> Int64 {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytesFallback
        progressHandler(max(0, totalBytesWritten), max(1, expected))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard
            let response = downloadTask.response as? HTTPURLResponse,
            (200...299).contains(response.statusCode)
        else {
            continuation?.resume(
                throwing: DownloadFailureReason.downloadFailed(
                    String(
                        format: String(localized: "Serwer zwrócił niepoprawny kod odpowiedzi dla %@"),
                        fileName
                    )
                )
            )
            continuation = nil
            return
        }

        do {
            let destinationDirectory = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? NSNumber)?
                .int64Value ?? expectedBytesFallback
            continuation?.resume(returning: max(0, fileSize))
        } catch {
            continuation?.resume(
                throwing: DownloadFailureReason.downloadFailed(
                    String(
                        format: String(localized: "Nie udało się zapisać pliku %@: %@"),
                        fileName,
                        error.localizedDescription
                    )
                )
            )
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if let urlError = error as? URLError {
            continuation?.resume(throwing: urlError)
        } else {
            continuation?.resume(throwing: DownloadFailureReason.downloadFailed(error.localizedDescription))
        }
        continuation = nil
    }
}
