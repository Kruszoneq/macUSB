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
    case cleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            return String(localized: "Wybrana pozycja nie jest wspierana w aktualnym pobieraniu")
        case let .insufficientDiskSpace(requiredMinimumBytes, availableBytes, installerBytes):
            return String(
                format: String(localized: "Brak wolnego miejsca: wymagane minimum %@ (250%% rozmiaru instalatora %@), dostępne %@."),
                DownloadManifestItem.formatBytes(requiredMinimumBytes),
                DownloadManifestItem.formatBytes(installerBytes),
                DownloadManifestItem.formatBytes(availableBytes)
            )
        case let .sessionInitializationFailed(details):
            return String(
                format: String(localized: "Nie udało się rozpocząć pobierania. Nie udało się przygotować sesji pobierania: %@"),
                details
            )
        case let .downloadFailed(details):
            return String(
                format: String(localized: "Nie udało się pobrać plików instalatora: %@"),
                details
            )
        case let .verificationFailed(details):
            return String(
                format: String(localized: "Weryfikacja plików nie powiodła się: %@"),
                details
            )
        case let .assemblyFailed(details):
            return String(
                format: String(localized: "Nie udało się przygotować instalatora: %@"),
                details
            )
        case let .cleanupFailed(details):
            return String(
                format: String(localized: "Usuwanie plików tymczasowych nie zostało ukończone: %@"),
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

    @Published var connectionStatusText: String = String(localized: "Łączenie z serwerami Apple...")
    @Published var downloadCurrentIndex: Int = 0
    @Published var downloadTotal: Int = 0
    @Published var downloadFileName: String = String(localized: "Oczekiwanie...")
    @Published var downloadProgress: Double = 0
    @Published var downloadSpeedText: String = "0.0 MB/s"
    @Published var downloadTransferredText: String = "0.0MB/0.0MB"
    @Published var verifyCurrentIndex: Int = 0
    @Published var verifyTotal: Int = 0
    @Published var verifyFileName: String = String(localized: "Oczekiwanie...")
    @Published var verifyProgress: Double = 0
    @Published var buildStatusText: String = String(localized: "Przygotowywanie instalatora...")
    @Published var buildProgress: Double? = nil
    @Published var cleanupStatusText: String = String(localized: "Przygotowanie czyszczenia...")
    @Published var cleanupProgress: Double = 0
    @Published var summaryTotalDownloadedText: String = "0.0 GB"
    @Published var summaryAverageSpeedText: String = "0.0 MB/s"
    @Published var summaryDurationText: String = String(
        format: String(localized: "%02dm %02ds"),
        0,
        0
    )
    @Published var summaryLocationText: String = String(localized: "Brak danych")
    @Published var summaryTemporaryFilesText: String = String(localized: "Brak danych")
    @Published var summaryCreatedFileText: String = String(localized: "Brak danych")
    @Published var discoveredDownloadItems: [DownloadManifestItem] = []
    @Published var pendingDiskSpaceAlert: DiskSpaceAlertContext?
    @Published var suppressInlineFailureMessage: Bool = false

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
        networkWarningMessage = nil
        hasExpiredButTrustedAppleSignature = false

        connectionStatusText = String(localized: "Łączenie z serwerami Apple...")
        downloadCurrentIndex = 0
        downloadTotal = 0
        downloadFileName = String(localized: "Oczekiwanie...")
        downloadProgress = 0
        downloadSpeedText = "0.0 MB/s"
        downloadTransferredText = "0.0MB/0.0MB"
        verifyCurrentIndex = 0
        verifyTotal = 0
        verifyFileName = String(localized: "Oczekiwanie...")
        verifyProgress = 0
        buildStatusText = String(localized: "Przygotowywanie instalatora...")
        buildProgress = nil
        cleanupStatusText = String(localized: "Przygotowanie czyszczenia...")
        cleanupProgress = 0
        summaryTotalDownloadedText = "0.0 GB"
        summaryAverageSpeedText = "0.0 MB/s"
        summaryDurationText = String(
            format: String(localized: "%02dm %02ds"),
            0,
            0
        )
        summaryLocationText = String(localized: "Brak danych")
        summaryTemporaryFilesText = String(localized: "Brak danych")
        summaryCreatedFileText = String(localized: "Brak danych")
        discoveredDownloadItems = []
        pendingDiskSpaceAlert = nil
        suppressInlineFailureMessage = false

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
}
