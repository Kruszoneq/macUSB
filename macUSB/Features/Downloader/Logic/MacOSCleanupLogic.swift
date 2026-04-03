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
                cleanupStatusText = "Tryb DEBUG: pliki sesji pozostawiono po sukcesie..."
            case .failed:
                cleanupStatusText = "Tryb DEBUG: pliki sesji pozostawiono po błędzie..."
            case .cancelled:
                cleanupStatusText = "Tryb DEBUG: pliki sesji pozostawiono po anulowaniu..."
            }
            summaryTemporaryFilesText = "Pozostawione w trybie DEBUG"
            cleanupProgress = 1
            completedStages.insert(.cleanup)
            return
        }

        if cleanupDelegatedToHelper {
            if sessionCleanupHandledByHelper {
                cleanupStatusText = "Pliki tymczasowe zostały usunięte..."
                summaryTemporaryFilesText = "Usunięte automatycznie"
                cleanupProgress = 1
                completedStages.insert(.cleanup)
                return
            }
            let reason = helperCleanupFailureMessage ?? "Helper nie potwierdził usunięcia plików tymczasowych"
            cleanupWarningMessage = "Instalator jest gotowy, ale pliki tymczasowe nie zostaly usuniete automatycznie. Szczegoly znajdziesz w logach"
            cleanupStatusText = "Cleanup zakończony z ostrzeżeniem..."
            summaryTemporaryFilesText = "Wymaga ręcznego usunięcia"
            cleanupProgress = 1
            completedStages.insert(.cleanup)
            AppLogging.error(
                "Helper cleanup niepotwierdzony: \(reason)",
                category: "Downloader"
            )
            return
        }

        guard let sessionRootURL = activeSessionRootURL else {
            cleanupStatusText = "Brak plików tymczasowych do usunięcia..."
            summaryTemporaryFilesText = "Brak plików tymczasowych"
            cleanupProgress = 1
            completedStages.insert(.cleanup)
            return
        }

        cleanupStatusText = "Usuwanie plików tymczasowych sesji..."
        cleanupProgress = 0.2

        do {
            let helperResult = try await requestHelperCleanup(sessionRootURL: sessionRootURL)
            if !helperResult.success {
                throw DownloadFailureReason.cleanupFailed(
                    helperResult.errorMessage ?? "Helper nie potwierdzil usuniecia katalogu sesji"
                )
            }
            activeSessionRootURL = nil
            activeSessionPayloadURL = nil
            activeSessionOutputURL = nil
            cleanupProgress = 1
            completedStages.insert(.cleanup)
            cleanupStatusText = "Pliki tymczasowe zostały usunięte..."
            summaryTemporaryFilesText = "Usunięte automatycznie"
        } catch {
            summaryTemporaryFilesText = "Nie usunięto plików tymczasowych"
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
        summaryCreatedFileText = finalInstallerAppURL?.lastPathComponent ?? "Nie utworzono instalatora"
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return String(format: "%02dm %02ds", minutes, remainder)
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
