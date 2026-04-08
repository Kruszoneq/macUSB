import Foundation
import AppKit

extension MontereyDownloadFlowModel {
    enum CleanupCompletionReason {
        case success
        case failed
        case cancelled
    }

    func runCleanup(completionReason: CleanupCompletionReason) async throws {
        currentStage = .cleanup
        cleanupProgress = 0

        if shouldRetainSessionFilesForDebugMode() {
            switch completionReason {
            case .success:
                cleanupStatusText = String(localized: "Tryb DEBUG: pliki sesji pozostawiono po sukcesie...")
            case .failed:
                cleanupStatusText = String(localized: "Tryb DEBUG: pliki sesji pozostawiono po błędzie...")
            case .cancelled:
                cleanupStatusText = String(localized: "Tryb DEBUG: pliki sesji pozostawiono po anulowaniu...")
            }
            summaryTemporaryFilesText = String(localized: "Pozostawione (tryb DEBUG)")
            cleanupProgress = 1
            completedStages.insert(.cleanup)
            return
        }

        if cleanupDelegatedToHelper {
            if sessionCleanupHandledByHelper {
                cleanupStatusText = String(localized: "Kończenie pracy...")
                summaryTemporaryFilesText = String(localized: "Zakończone automatycznie")
                cleanupProgress = 1
                completedStages.insert(.cleanup)
                return
            }
            let reason = helperCleanupFailureMessage ?? String(localized: "Helper nie potwierdził usunięcia plików tymczasowych")
            cleanupWarningMessage = String(localized: "Instalator został przygotowany, ale usuwanie plików tymczasowych nie zostało ukończone automatycznie.")
            cleanupStatusText = String(localized: "Kończenie pracy z ostrzeżeniem...")
            summaryTemporaryFilesText = String(localized: "Wymaga ręcznego dokończenia")
            cleanupProgress = 1
            completedStages.insert(.cleanup)
            AppLogging.error(
                "Helper cleanup niepotwierdzony: \(reason)",
                category: "Downloader"
            )
            return
        }

        guard let sessionRootURL = activeSessionRootURL else {
            cleanupStatusText = String(localized: "Kończenie pracy...")
            summaryTemporaryFilesText = String(localized: "Brak danych do porządkowania")
            cleanupProgress = 1
            completedStages.insert(.cleanup)
            return
        }

        cleanupStatusText = String(localized: "Porządkowanie plików tymczasowych...")
        cleanupProgress = 0.2

        do {
            let helperResult = try await requestHelperCleanup(sessionRootURL: sessionRootURL)
            if !helperResult.success {
                throw DownloadFailureReason.cleanupFailed(
                    helperResult.errorMessage ?? String(localized: "Helper nie potwierdził usunięcia katalogu sesji")
                )
            }
            activeSessionRootURL = nil
            activeSessionPayloadURL = nil
            activeSessionOutputURL = nil
            cleanupProgress = 1
            completedStages.insert(.cleanup)
            cleanupStatusText = String(localized: "Kończenie pracy...")
            summaryTemporaryFilesText = String(localized: "Zakończone automatycznie")
        } catch {
            summaryTemporaryFilesText = String(localized: "Nieukończone")
            throw DownloadFailureReason.cleanupFailed(error.localizedDescription)
        }
    }

    private func requestHelperCleanup(
        sessionRootURL: URL
    ) async throws -> DownloaderCleanupResultPayload {
        let request = DownloaderCleanupRequestPayload(sessionRootPath: sessionRootURL.path)
        return await withCheckedContinuation { continuation in
            PrivilegedOperationClient.shared.cleanupDownloaderSession(request: request) { result in
                continuation.resume(returning: result)
            }
        }
    }

    func updateSummaryMetrics() {
        let totalDownloadedGB = Double(totalDownloadedBytes) / 1_000_000_000
        summaryTotalDownloadedText = "\(formatDecimal(totalDownloadedGB, fractionDigits: 1)) GB"

        let averageSpeed = speedSamplesMBps.isEmpty
            ? 0
            : speedSamplesMBps.reduce(0, +) / Double(speedSamplesMBps.count)
        summaryAverageSpeedText = "\(formatDecimal(averageSpeed, fractionDigits: 1)) MB/s"

        let durationSeconds: TimeInterval
        if let processStartedAt {
            durationSeconds = max(0, Date().timeIntervalSince(processStartedAt))
        } else {
            durationSeconds = 0
        }
        summaryDurationText = formatDuration(durationSeconds)
        summaryCreatedFileText = finalInstallerAppURL?.lastPathComponent ?? String(localized: "Nie utworzono instalatora")
        summaryLocationText = finalInstallerAppURL?.deletingLastPathComponent().path ?? String(localized: "Brak danych")
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return String(
            format: String(localized: "%02dm %02ds"),
            minutes,
            remainder
        )
    }

    func playCompletionSound(success: Bool) {
        if didPlayCompletionSound { return }
        didPlayCompletionSound = true

        if !success {
            if let failSound = NSSound(named: NSSound.Name("Basso")) {
                failSound.play()
            }
            return
        }

        let bundledSoundURL =
            Bundle.main.url(forResource: "burn_complete", withExtension: "aif", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: "burn_complete", withExtension: "aif")

        if let bundledSoundURL,
           let successSound = NSSound(contentsOf: bundledSoundURL, byReference: false) {
            successSound.play()
        } else if let successSound = NSSound(named: NSSound.Name("burn_success")) {
            successSound.play()
        } else if let successSound = NSSound(named: NSSound.Name("Glass")) {
            successSound.play()
        } else if let hero = NSSound(named: NSSound.Name("Hero")) {
            hero.play()
        }
    }

    func cleanupTemporaryDownloadsFolder() {
        let temporaryDownloadsURL = downloaderSessionsRootURL()

        guard FileManager.default.fileExists(atPath: temporaryDownloadsURL.path) else {
            AppLogging.info(
                "Cleanup downloadera: brak katalogu tymczasowego do usuniecia.",
                category: "Downloader"
            )
            return
        }

        do {
            try FileManager.default.removeItem(at: temporaryDownloadsURL)
            AppLogging.info(
                "Cleanup downloadera: usunieto katalog tymczasowy pobierania.",
                category: "Downloader"
            )
        } catch {
            AppLogging.error(
                "Cleanup downloadera nie powiodl sie: \(error.localizedDescription)",
                category: "Downloader"
            )
        }
    }
}
