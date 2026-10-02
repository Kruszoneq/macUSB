import Foundation
import Combine

enum LinuxDownloadFlowStage: Int, CaseIterable {
    case connection
    case downloading
    case verifying
    case finalizing
}

enum LinuxDownloadFailureReason: LocalizedError {
    case destinationUnavailable
    case downloadFailed(String)
    case checksumMismatch
    case verificationFailed(String)
    case moveFailed(String)

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable:
            return String(localized: "downloader.linux.error.destination_unavailable")
        case let .downloadFailed(details):
            return String(format: String(localized: "downloader.linux.error.download"), details)
        case .checksumMismatch:
            return String(localized: "downloader.linux.error.checksum_mismatch")
        case let .verificationFailed(details):
            return String(format: String(localized: "downloader.linux.error.verification"), details)
        case let .moveFailed(details):
            return String(format: String(localized: "downloader.linux.error.move"), details)
        }
    }
}

struct LinuxDownloadInsufficientSpace: Error {
    let requiredBytes: Int64
    let availableBytes: Int64
}

@MainActor
final class LinuxDownloadFlowModel: ObservableObject {
    @Published var currentStage: LinuxDownloadFlowStage = .connection
    @Published var completedStages: Set<LinuxDownloadFlowStage> = []
    @Published var isFinished: Bool = false
    @Published var workflowState: DownloadSessionState = .idle
    @Published var failureMessage: String?

    @Published var connectionStatusText: String = ""
    @Published var downloadProgress: Double = 0
    @Published var downloadSpeedText: String = "0.0 MB/s"
    @Published var downloadTransferredText: String = "0.0MB/0.0MB"
    @Published var verifyProgress: Double = 0
    @Published var finalizeStatusText: String = ""

    @Published var summaryTotalDownloadedText: String = "0.0 GB"
    @Published var summaryAverageSpeedText: String = "0.0 MB/s"
    @Published var summaryDurationText: String = ""
    @Published var pendingDiskSpaceAlert: DiskSpaceAlertContext?

    var activeEntry: LinuxImageEntry?
    var finalImageURL: URL?

    var workflowTask: Task<Void, Never>?
    var processStartedAt: Date?
    var totalDownloadedBytes: Int64 = 0
    var speedSamplesMBps: [Double] = []
    var lastSpeedSampleDate = Date()
    var lastSpeedSampleBytes: Int64 = 0
    var activeSessionRootURL: URL?
    var activeDownloadTask: URLSessionDownloadTask?
    var activeDownloadSession: URLSession?
    var activeDownloadTaskDelegate: FileDownloadTaskDelegate?

    func start(for entry: LinuxImageEntry, destinationDirectoryURL: URL) {
        stop()
        resetState()
        activeEntry = entry

        workflowTask = Task { [weak self] in
            await self?.runWorkflow(for: entry, destinationDirectoryURL: destinationDirectoryURL)
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
        removeSessionDirectory()
    }

    func visualState(for stage: LinuxDownloadFlowStage) -> DownloadStageVisualState {
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

        connectionStatusText = ""
        downloadProgress = 0
        downloadSpeedText = "0.0 MB/s"
        downloadTransferredText = "0.0MB/0.0MB"
        verifyProgress = 0
        finalizeStatusText = ""

        summaryTotalDownloadedText = "0.0 GB"
        summaryAverageSpeedText = "0.0 MB/s"
        summaryDurationText = String(format: String(localized: "%02dm %02ds"), 0, 0)
        pendingDiskSpaceAlert = nil

        activeEntry = nil
        finalImageURL = nil
        processStartedAt = Date()
        totalDownloadedBytes = 0
        speedSamplesMBps = []
        activeSessionRootURL = nil
    }

    func removeSessionDirectory() {
        guard let activeSessionRootURL else { return }
        do {
            if FileManager.default.fileExists(atPath: activeSessionRootURL.path) {
                try FileManager.default.removeItem(at: activeSessionRootURL)
            }
            AppLogging.info(
                "Removed download session directory \(activeSessionRootURL.path).",
                stage: .downloader, workflow: .linux
            )
        } catch {
            AppLogging.error(
                "Failed to remove download session directory \(activeSessionRootURL.path): \(error.localizedDescription)",
                stage: .downloader, workflow: .linux
            )
        }
        self.activeSessionRootURL = nil
    }
}
