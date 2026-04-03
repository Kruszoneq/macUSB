import Foundation
import Combine

enum DownloadStageVisualState {
    case pending
    case active
    case completed
}

enum MontereyDownloadFlowStage: Int, CaseIterable {
    case connection
    case downloading
    case verifying
    case buildingInstaller
    case copyingInstaller
    case cleanup
}

enum DownloadSessionState: Equatable {
    case idle
    case running
    case completed
    case failed
    case cancelled
}

enum DownloadFailureReason: LocalizedError {
    case unsupportedSelection
    case sessionInitializationFailed(String)
    case downloadFailed(String)
    case verificationFailed(String)
    case assemblyFailed(String)
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            return "Wybrana pozycja nie jest wspierana w aktualnym pobieraniu"
        case let .sessionInitializationFailed(details):
            return "Nie udalo sie przygotowac sesji pobierania: \(details)"
        case let .downloadFailed(details):
            return "Pobieranie nie powiodlo sie: \(details)"
        case let .verificationFailed(details):
            return "Weryfikacja plikow nie powiodla sie: \(details)"
        case let .assemblyFailed(details):
            return "Budowanie instalatora nie powiodlo sie: \(details)"
        case let .cleanupFailed(details):
            return "Czyszczenie plikow tymczasowych nie powiodlo sie: \(details)"
        }
    }
}

struct DownloadManifestItem: Identifiable, Hashable {
    let order: Int
    let name: String
    let url: URL
    let expectedSizeBytes: Int64
    let expectedDigest: String?
    let digestAlgorithm: String?
    let integrityDataURL: URL?

    var id: String { "\(order)|\(name)|\(url.absoluteString)" }

    var expectedSizeText: String {
        Self.formatBytes(expectedSizeBytes)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1_000_000_000 {
            let mb = Double(bytes) / 1_000_000
            return String(format: "%.1fMB", locale: Locale(identifier: "en_US_POSIX"), mb)
        }
        let gb = Double(bytes) / 1_000_000_000
        return String(format: "%.2fGB", locale: Locale(identifier: "en_US_POSIX"), gb)
    }
}

struct DownloadManifest: Hashable {
    let productID: String
    let systemName: String
    let systemVersion: String
    let systemBuild: String
    let items: [DownloadManifestItem]
    let totalExpectedBytes: Int64
}

@MainActor
final class MontereyDownloadFlowModel: ObservableObject {
    @Published var currentStage: MontereyDownloadFlowStage = .connection
    @Published var completedStages: Set<MontereyDownloadFlowStage> = []
    @Published var isFinished: Bool = false
    @Published var workflowState: DownloadSessionState = .idle
    @Published var failureMessage: String?
    @Published var isPartialSuccess: Bool = false
    @Published var cleanupWarningMessage: String?

    @Published var connectionStatusText: String = "Weryfikuję połączenie z serwerami Apple..."
    @Published var downloadCurrentIndex: Int = 0
    @Published var downloadTotal: Int = 0
    @Published var downloadFileName: String = "Oczekiwanie na plik..."
    @Published var downloadProgress: Double = 0
    @Published var downloadSpeedText: String = "0.0 MB/s"
    @Published var downloadTransferredText: String = "0.0MB/0.0MB"
    @Published var verifyCurrentIndex: Int = 0
    @Published var verifyTotal: Int = 0
    @Published var verifyFileName: String = "Oczekiwanie na plik..."
    @Published var verifyProgress: Double = 0
    @Published var buildStatusText: String = "Przygotowywanie środowiska budowania..."
    @Published var buildProgress: Double? = nil
    @Published var copyStatusText: String = "Przygotowanie kopiowania instalatora..."
    @Published var copyProgress: Double = 0
    @Published var cleanupStatusText: String = "Przygotowanie czyszczenia..."
    @Published var cleanupProgress: Double = 0
    @Published var summaryTotalDownloadedText: String = "0.0 GB"
    @Published var summaryAverageSpeedText: String = "0.0 MB/s"
    @Published var summaryDurationText: String = "00m 00s"
    @Published var summaryTemporaryFilesText: String = "Brak danych"
    @Published var summaryCreatedFileText: String = "Brak danych"
    @Published var discoveredDownloadItems: [DownloadManifestItem] = []

    @Published var preserveDownloadedFilesInDebug: Bool = false

    var workflowTask: Task<Void, Never>?
    var processStartedAt: Date?
    var totalDownloadedBytes: Int64 = 0
    var speedSamplesMBps: [Double] = []
    var didPlayCompletionSound: Bool = false

    var activeManifest: DownloadManifest?
    var activeSessionID: String?
    var activeSessionRootURL: URL?
    var activeSessionPayloadURL: URL?
    var activeSessionOutputURL: URL?
    var cleanupDelegatedToHelper: Bool = false
    var sessionCleanupHandledByHelper: Bool = false
    var helperCleanupFailureMessage: String?
    var downloadedFileURLsByItemID: [String: URL] = [:]
    var finalInstallerAppURL: URL?

    var activeDownloadTask: URLSessionDownloadTask?
    var activeDownloadSession: URLSession?
    var activeDownloadTaskDelegate: FileDownloadTaskDelegate?

    var activeAssemblyWorkflowID: String?

    func start(for entry: MacOSInstallerEntry, using logic: MacOSDownloaderLogic) {
        stop()
        resetState()

        workflowTask = Task { [weak self] in
            guard let self else { return }
            await runWorkflow(for: entry, using: logic)
        }
    }

    func stop() {
        workflowTask?.cancel()
        workflowTask = nil

        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadSession?.invalidateAndCancel()
        activeDownloadSession = nil
        activeDownloadTaskDelegate = nil

        if let activeAssemblyWorkflowID {
            PrivilegedOperationClient.shared.cancelDownloaderAssembly(activeAssemblyWorkflowID) { _, _ in }
            self.activeAssemblyWorkflowID = nil
        }
    }

    func visualState(for stage: MontereyDownloadFlowStage) -> DownloadStageVisualState {
        if completedStages.contains(stage) {
            return .completed
        }
        if !isFinished && currentStage == stage {
            return .active
        }
        return .pending
    }

    func resetState() {
        currentStage = .connection
        completedStages = []
        isFinished = false
        workflowState = .idle
        failureMessage = nil
        isPartialSuccess = false
        cleanupWarningMessage = nil

        connectionStatusText = "Weryfikuję połączenie z serwerami Apple..."
        downloadCurrentIndex = 0
        downloadTotal = 0
        downloadFileName = "Oczekiwanie na plik..."
        downloadProgress = 0
        downloadSpeedText = "0.0 MB/s"
        downloadTransferredText = "0.0MB/0.0MB"
        verifyCurrentIndex = 0
        verifyTotal = 0
        verifyFileName = "Oczekiwanie na plik..."
        verifyProgress = 0
        buildStatusText = "Przygotowywanie środowiska budowania..."
        buildProgress = nil
        copyStatusText = "Przygotowanie kopiowania instalatora..."
        copyProgress = 0
        cleanupStatusText = "Przygotowanie czyszczenia..."
        cleanupProgress = 0
        summaryTotalDownloadedText = "0.0 GB"
        summaryAverageSpeedText = "0.0 MB/s"
        summaryDurationText = "00m 00s"
        summaryTemporaryFilesText = "Brak danych"
        summaryCreatedFileText = "Brak danych"
        discoveredDownloadItems = []

        processStartedAt = Date()
        totalDownloadedBytes = 0
        speedSamplesMBps = []
        didPlayCompletionSound = false
        activeManifest = nil
        activeSessionID = nil
        activeSessionRootURL = nil
        activeSessionPayloadURL = nil
        activeSessionOutputURL = nil
        cleanupDelegatedToHelper = false
        sessionCleanupHandledByHelper = false
        helperCleanupFailureMessage = nil
        downloadedFileURLsByItemID = [:]
        finalInstallerAppURL = nil
    }

    func runWorkflow(for entry: MacOSInstallerEntry, using logic: MacOSDownloaderLogic) async {
        workflowState = .running

        do {
            let manifest = try await runConnectionCheck(for: entry, using: logic)
            activeManifest = manifest
            discoveredDownloadItems = manifest.items

            try prepareSessionDirectories()
            try await runFileDownloads(manifest: manifest)
            try await runFileVerification(manifest: manifest)
            try await runInstallerBuild(manifest: manifest, entry: entry)
            try await runCleanup(completionReason: .success)

            updateSummaryMetrics()
            isFinished = true
            if let cleanupWarningMessage, !cleanupWarningMessage.isEmpty {
                failureMessage = cleanupWarningMessage
                isPartialSuccess = finalInstallerAppURL != nil
                workflowState = .failed
                playCompletionSound(success: true)
            } else {
                workflowState = .completed
                playCompletionSound(success: true)
            }
        } catch is CancellationError {
            workflowState = .cancelled
            failureMessage = nil

            do {
                try await runCleanup(completionReason: .cancelled)
            } catch {
                AppLogging.error(
                    "Cleanup po anulowaniu pobierania nie powiodl sie: \(error.localizedDescription)",
                    category: "Downloader"
                )
            }
        } catch {
            let technicalMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            failureMessage = userFacingFailureMessage(for: technicalMessage)
            workflowState = .failed
            let isCleanupFailure = {
                if case DownloadFailureReason.cleanupFailed = error { return true }
                return false
            }()

            AppLogging.error(
                "Pobieranie Monterey zakonczone bledem: \(technicalMessage)",
                category: "Downloader"
            )

            if !isCleanupFailure {
                do {
                    try await runCleanup(completionReason: .failed)
                } catch {
                    AppLogging.error(
                        "Cleanup po bledzie pobierania nie powiodl sie: \(error.localizedDescription)",
                        category: "Downloader"
                    )
                }
            }

            if isCleanupFailure, finalInstallerAppURL != nil {
                isPartialSuccess = true
                failureMessage = "Instalator jest gotowy, ale nie udalo sie usunac plikow tymczasowych. Szczegoly znajdziesz w logach"
            } else {
                isPartialSuccess = (finalInstallerAppURL != nil) && completedStages.contains(.cleanup)
            }
            updateSummaryMetrics()
            playCompletionSound(success: false)
            isFinished = true
        }
    }

    private func userFacingFailureMessage(for technicalMessage: String) -> String {
        if isMovePermissionFailure(technicalMessage) {
            return "Nie udało się przenieść instalatora do folderu docelowego z powodu braku uprawnień. Sprawdź uprawnienia wybranego folderu i spróbuj ponownie. Szczegóły techniczne znajdziesz w logach"
        }
        return technicalMessage
    }

    private func isMovePermissionFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let moveFailure =
            normalized.contains("nie można przenieść")
            || (normalized.contains("cannot") && normalized.contains("move"))
        let permissionFailure =
            normalized.contains("nie masz praw dostępu")
            || normalized.contains("permission")
            || normalized.contains("access")
        return moveFailure && permissionFailure
    }

    func runConnectionCheck(
        for entry: MacOSInstallerEntry,
        using logic: MacOSDownloaderLogic
    ) async throws -> DownloadManifest {
        currentStage = .connection
        connectionStatusText = "Łączę się z serwerami Apple i pobieram manifest Monterey..."

        let manifest = try await logic.prepareDownloadManifest(for: entry) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.connectionStatusText = "\(status)..."
            }
        }

        for item in manifest.items {
            let digestPreview: String
            if let digest = item.expectedDigest, !digest.isEmpty {
                let trimmed = digest.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 16 {
                    digestPreview = "\(trimmed.prefix(8))...\(trimmed.suffix(8))"
                } else {
                    digestPreview = trimmed
                }
            } else {
                digestPreview = "brak"
            }
            AppLogging.info(
                "Manifest Monterey item: name=\(item.name), size=\(item.expectedSizeBytes), digest=\(digestPreview), url=\(item.url.absoluteString)",
                category: "Downloader"
            )
        }

        connectionStatusText = "Sprawdzam dostepne miejsce w katalogu tymczasowym..."
        try verifyTemporaryDiskCapacity(requiredBytes: manifest.totalExpectedBytes)

        downloadTotal = manifest.items.count
        verifyTotal = manifest.items.count
        connectionStatusText = "Wykryto \(manifest.items.count) plików o łącznym rozmiarze \(DownloadManifestItem.formatBytes(manifest.totalExpectedBytes))..."
        completedStages.insert(.connection)
        return manifest
    }

    func verifyTemporaryDiskCapacity(requiredBytes: Int64) throws {
        let probeURL = FileManager.default.temporaryDirectory
        let reserveBytes: Int64 = max(2_000_000_000, Int64(Double(requiredBytes) * 0.10))
        let minimumRequired = requiredBytes + reserveBytes

        let values = try probeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let availableBytes = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        guard availableBytes >= minimumRequired else {
            throw DownloadFailureReason.sessionInitializationFailed(
                "Brak wolnego miejsca: wymagane \(DownloadManifestItem.formatBytes(minimumRequired)), dostepne \(DownloadManifestItem.formatBytes(availableBytes))."
            )
        }
    }

    func prepareSessionDirectories() throws {
        let sessionID = UUID().uuidString.lowercased()
        let rootURL = downloaderSessionsRootURL()
            .appendingPathComponent(sessionID, isDirectory: true)
        let payloadURL = rootURL.appendingPathComponent("payload", isDirectory: true)
        let outputURL = rootURL.appendingPathComponent("output", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: payloadURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw DownloadFailureReason.sessionInitializationFailed(error.localizedDescription)
        }

        activeSessionID = sessionID
        activeSessionRootURL = rootURL
        activeSessionPayloadURL = payloadURL
        activeSessionOutputURL = outputURL
    }

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
                throw DownloadFailureReason.sessionInitializationFailed("Brak katalogu payload sesji")
            }

            downloadCurrentIndex = index + 1
            downloadFileName = item.name

            let itemDestinationURL = payloadURL.appendingPathComponent("\(index + 1)_\(sanitizeFileName(item.name))")
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

    func downloadItemWithRetry(
        _ item: DownloadManifestItem,
        destinationURL: URL,
        maxAttempts: Int,
        progress: @escaping @MainActor (_ receivedBytes: Int64, _ expectedBytes: Int64) -> Void
    ) async throws -> Int64 {
        let attempts = max(1, maxAttempts)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await downloadItem(item, to: destinationURL, progress: progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < attempts {
                    let delayNanoseconds = UInt64(500_000_000 * attempt * attempt)
                    AppLogging.info(
                        "Retry pobierania pliku \(item.name): proba \(attempt + 1)/\(attempts), opoznienie \(delayNanoseconds / 1_000_000) ms.",
                        category: "Downloader"
                    )
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    continue
                }
            }
        }

        throw lastError ?? DownloadFailureReason.downloadFailed("Nieznany blad pobierania")
    }

    func shouldRetainSessionFilesForDebugMode() -> Bool {
        #if DEBUG
        return preserveDownloadedFilesInDebug
        #else
        return false
        #endif
    }

    func downloaderSessionsRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("macUSB_temp", isDirectory: true)
            .appendingPathComponent("downloads", isDirectory: true)
    }

    func sanitizeFileName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "_",
            options: .regularExpression
        )
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
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
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
                    "Serwer zwrocil niepoprawny kod odpowiedzi dla \(fileName)"
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
                    "Nie udalo sie zapisac pliku \(fileName): \(error.localizedDescription)"
                )
            )
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: DownloadFailureReason.downloadFailed(error.localizedDescription))
        continuation = nil
    }
}
