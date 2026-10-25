import Foundation
import Combine

enum DownloadStageVisualState: Hashable {
    case pending
    case active
    case completed
}

enum MontereyDownloadFlowStage: Int, CaseIterable {
    case connection
    case downloading
    case verifying
    case buildingInstaller
    case creatingDiskImage
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
    case insufficientDiskSpace(requiredMinimumBytes: Int64, availableBytes: Int64, installerBytes: Int64)
    case sessionInitializationFailed(String)
    case downloadFailed(String)
    case verificationFailed(String)
    case assemblyFailed(String)
    case diskImageCreationFailed(String)
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            return String(localized: "downloader.selection.error.unsupported", table: "Downloader")
        case let .insufficientDiskSpace(requiredMinimumBytes, availableBytes, installerBytes):
            return String(
                format: String(localized: "downloader.space.error.insufficient", table: "Downloader"),
                DownloadManifestItem.formatBytes(requiredMinimumBytes),
                DownloadManifestItem.formatBytes(installerBytes),
                DownloadManifestItem.formatBytes(availableBytes)
            )
        case let .sessionInitializationFailed(details):
            return String(
                format: String(localized: "downloader.session.error.initialization", table: "Downloader"),
                details
            )
        case let .downloadFailed(details):
            return String(
                format: String(localized: "downloader.transfer.error.failed", table: "Downloader"),
                details
            )
        case let .verificationFailed(details):
            return String(
                format: String(localized: "downloader.verification.error.failed", table: "Downloader"),
                details
            )
        case let .assemblyFailed(details):
            return String(
                format: String(localized: "downloader.assembly.error.failed", table: "Downloader"),
                details
            )
        case let .diskImageCreationFailed(details):
            return String(
                format: String(localized: "downloader.disk_image.error.creation", table: "Downloader"),
                details
            )
        case let .cleanupFailed(details):
            return String(
                format: String(localized: "downloader.cleanup.error.failed", table: "Downloader"),
                details
            )
        }
    }
}

let internetReconnectTimeoutSeconds = 60

struct DownloadManifestItem: Identifiable, Hashable {
    let order: Int
    let name: String
    let url: URL
    let packageIdentifier: String?
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
    let distributionURL: URL?
    let items: [DownloadManifestItem]
    let totalExpectedBytes: Int64
}

struct DiskSpaceAlertContext: Equatable {
    let requiredMinimumText: String
    let availableText: String
    var diskImageLocation: MacOSDiskImageSpaceLocation? = nil
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
    @Published var networkWarningMessage: String?
    @Published var hasExpiredButTrustedAppleSignature: Bool = false

    @Published var connectionStatusText: String = String(localized: "downloader.connection.status.connecting", table: "Downloader")
    @Published var downloadCurrentIndex: Int = 0
    @Published var downloadTotal: Int = 0
    @Published var downloadFileName: String = String(localized: "downloader.transfer.status.waiting", table: "Downloader")
    @Published var downloadProgress: Double = 0
    @Published var downloadSpeedText: String = "0.0 MB/s"
    @Published var downloadTransferredText: String = "0.0MB/0.0MB"
    @Published var verifyCurrentIndex: Int = 0
    @Published var verifyTotal: Int = 0
    @Published var verifyFileName: String = String(localized: "downloader.transfer.status.waiting", table: "Downloader")
    @Published var verifyProgress: Double = 0
    @Published var buildStatusText: String = String(localized: "downloader.assembly.status.preparing_installer", table: "Downloader")
    @Published var buildProgress: Double? = nil
    @Published var diskImageStageStatus: MacOSDiskImageStageStatus = .preparing
    @Published var cleanupStatusText: String = String(localized: "downloader.cleanup.status.preparing", table: "Downloader")
    @Published var cleanupProgress: Double = 0
    @Published var summaryTotalDownloadedText: String = "0.0 GB"
    @Published var summaryAverageSpeedText: String = "0.0 MB/s"
    @Published var summaryDurationText: String = String(
        format: String(localized: "downloader.summary.duration.format", table: "Downloader"),
        0,
        0
    )
    @Published var summaryLocationText: String = String(localized: "downloader.summary.value.unavailable", table: "Downloader")
    @Published var summaryTemporaryFilesText: String = String(localized: "downloader.summary.value.unavailable", table: "Downloader")
    @Published var summaryCreatedFileText: String = String(localized: "downloader.summary.value.unavailable", table: "Downloader")
    @Published var discoveredDownloadItems: [DownloadManifestItem] = []
    @Published var pendingDiskSpaceAlert: DiskSpaceAlertContext?
    @Published var suppressInlineFailureMessage: Bool = false
    @Published var didCancelDiskImagePreflight: Bool = false
    @Published var pendingDiskImageFolderUnavailableAlert: Bool = false

    @Published var preserveDownloadedFilesInDebug: Bool = false

    var workflowTask: Task<Void, Never>?
    var processStartedAt: Date?
    var totalDownloadedBytes: Int64 = 0
    var speedSamplesMBps: [Double] = []
    var didPlayCompletionSound: Bool = false

    var activeManifest: DownloadManifest?
    var loggingWorkflow: AppLogging.Workflow = .modern
    var activeSessionID: String?
    var activeSessionRootURL: URL?
    var activeSessionPayloadURL: URL?
    var activeSessionOutputURL: URL?
    var cleanupDelegatedToHelper: Bool = false
    var sessionCleanupHandledByHelper: Bool = false
    var helperCleanupFailureMessage: String?
    var downloadedFileURLsByItemID: [String: URL] = [:]
    var finalInstallerAppURL: URL?
    var finalDiskImageURL: URL?
    var retainedSourceInstallerURL: URL?
    var activeDiskImageConfiguration: MacOSDiskImageConfiguration = .disabled
    var activeDiskImagePreflightPlan: MacOSDiskImagePreflightPlan?
    var diskImageSourceRemovalWarning: Bool = false
    let diskImageProcessRunner = MacOSDiskImageProcessRunner()

    var activeDownloadTask: URLSessionDownloadTask?
    var activeDownloadSession: URLSession?
    var activeDownloadTaskDelegate: FileDownloadTaskDelegate?

    var activeAssemblyWorkflowID: String?

    func start(
        for entry: MacOSInstallerEntry,
        using logic: MacOSDownloaderLogic,
        diskImageConfiguration: MacOSDiskImageConfiguration = .disabled,
        collisionDecision: @escaping @MainActor (MacOSDiskImageCollisionContext) -> Bool = { _ in false }
    ) {
        stop()
        resetState()
        activeDiskImageConfiguration = diskImageConfiguration

        workflowTask = Task { [weak self] in
            guard let self else { return }
            await runWorkflow(
                for: entry,
                using: logic,
                diskImageConfiguration: diskImageConfiguration,
                collisionDecision: collisionDecision
            )
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
        diskImageProcessRunner.cancel()
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
        networkWarningMessage = nil
        hasExpiredButTrustedAppleSignature = false

        connectionStatusText = String(localized: "downloader.connection.status.connecting", table: "Downloader")
        downloadCurrentIndex = 0
        downloadTotal = 0
        downloadFileName = String(localized: "downloader.transfer.status.waiting", table: "Downloader")
        downloadProgress = 0
        downloadSpeedText = "0.0 MB/s"
        downloadTransferredText = "0.0MB/0.0MB"
        verifyCurrentIndex = 0
        verifyTotal = 0
        verifyFileName = String(localized: "downloader.transfer.status.waiting", table: "Downloader")
        verifyProgress = 0
        buildStatusText = String(localized: "downloader.assembly.status.preparing_installer", table: "Downloader")
        buildProgress = nil
        diskImageStageStatus = .preparing
        cleanupStatusText = String(localized: "downloader.cleanup.status.preparing", table: "Downloader")
        cleanupProgress = 0
        summaryTotalDownloadedText = "0.0 GB"
        summaryAverageSpeedText = "0.0 MB/s"
        summaryDurationText = String(
            format: String(localized: "downloader.summary.duration.format", table: "Downloader"),
            0,
            0
        )
        summaryLocationText = String(localized: "downloader.summary.value.unavailable", table: "Downloader")
        summaryTemporaryFilesText = String(localized: "downloader.summary.value.unavailable", table: "Downloader")
        summaryCreatedFileText = String(localized: "downloader.summary.value.unavailable", table: "Downloader")
        discoveredDownloadItems = []
        pendingDiskSpaceAlert = nil
        suppressInlineFailureMessage = false
        didCancelDiskImagePreflight = false
        pendingDiskImageFolderUnavailableAlert = false

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
        finalDiskImageURL = nil
        retainedSourceInstallerURL = nil
        activeDiskImageConfiguration = .disabled
        activeDiskImagePreflightPlan = nil
        diskImageSourceRemovalWarning = false
    }
}
