import Foundation

extension MontereyDownloadFlowModel {
    func runWorkflow(
        for entry: MacOSInstallerEntry,
        using logic: MacOSDownloaderLogic,
        diskImageConfiguration: MacOSDiskImageConfiguration,
        collisionDecision: @escaping @MainActor (MacOSDiskImageCollisionContext) -> Bool
    ) async {
        let sleepBlockToken = SystemSleepBlocker.shared.begin(reason: "Pobieranie systemu macOS")
        defer { SystemSleepBlocker.shared.end(sleepBlockToken) }

        workflowState = .running
        activeDiskImageConfiguration = diskImageConfiguration

        do {
            let manifest = try await runConnectionCheck(
                for: entry,
                using: logic,
                diskImageConfiguration: diskImageConfiguration,
                collisionDecision: collisionDecision
            )
            activeManifest = manifest
            discoveredDownloadItems = manifest.items

            try prepareSessionDirectories()
            try await runFileDownloads(manifest: manifest)
            try await runFileVerification(manifest: manifest, entry: entry)
            try await runInstallerBuild(manifest: manifest, entry: entry)
            if diskImageConfiguration.isEnabled {
                do {
                    _ = try await runDiskImageCreation()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw DownloadFailureReason.diskImageCreationFailed(
                        diskImageTechnicalDescription(for: error)
                    )
                }
            }
            try await runCleanup(completionReason: .success)

            updateSummaryMetrics()
            isFinished = true
            if diskImageSourceRemovalWarning {
                isPartialSuccess = true
                workflowState = .failed
                playCompletionSound(success: true)
            } else if let cleanupWarningMessage, !cleanupWarningMessage.isEmpty {
                failureMessage = cleanupWarningMessage
                isPartialSuccess = finalInstallerAppURL != nil
                workflowState = .failed
                playCompletionSound(success: true)
            } else {
                workflowState = .completed
                playCompletionSound(success: true)
            }
        } catch is MacOSDiskImagePreflightCancelled {
            workflowState = .idle
            didCancelDiskImagePreflight = true
            activeDiskImagePreflightPlan = nil
        } catch let error as MacOSDiskImagePreflightError {
            workflowState = .idle
            suppressInlineFailureMessage = true
            activeDiskImagePreflightPlan = nil
            switch error {
            case let .insufficientSpace(location, requiredBytes, availableBytes):
                pendingDiskSpaceAlert = DiskSpaceAlertContext(
                    requiredMinimumText: formatDiskImageGigabytes(requiredBytes),
                    availableText: formatDiskImageGigabytes(availableBytes),
                    diskImageLocation: location
                )
            case .destinationUnavailable, .capacityUnavailable:
                pendingDiskImageFolderUnavailableAlert = true
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
            workflowState = .failed
            suppressInlineFailureMessage = false
            if let diskSpaceAlertContext = diskSpaceAlertContext(from: error) {
                pendingDiskSpaceAlert = diskSpaceAlertContext
                suppressInlineFailureMessage = true
            }
            let isCleanupFailure = {
                if case DownloadFailureReason.cleanupFailed = error { return true }
                return false
            }()

            AppLogging.error(
                "Pobieranie systemu zakonczone bledem: \(technicalMessage)",
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

            if isInternetTimeoutFailure(technicalMessage) {
                if completedStages.contains(.cleanup) {
                    failureMessage = String(localized: "Przez 1 minutę nie udało się odzyskać połączenia internetowego. Pliki tymczasowe zostały usunięte.")
                } else {
                    failureMessage = String(localized: "Przez 1 minutę nie udało się odzyskać połączenia internetowego. Nie udało się potwierdzić usunięcia plików tymczasowych.")
                }
            } else {
                failureMessage = userFacingFailureMessage(for: technicalMessage)
            }

            if isCleanupFailure, finalInstallerAppURL != nil {
                isPartialSuccess = true
                failureMessage = String(localized: "Instalator został przygotowany, ale usuwanie plików tymczasowych nie zostało ukończone automatycznie.")
            } else {
                isPartialSuccess = (finalInstallerAppURL != nil || finalDiskImageURL != nil)
                    && completedStages.contains(.cleanup)
            }
            updateSummaryMetrics()
            playCompletionSound(success: false)
            isFinished = true
        }
    }

    func diskSpaceAlertContext(from error: Error) -> DiskSpaceAlertContext? {
        guard let reason = error as? DownloadFailureReason else {
            return nil
        }
        guard case let .insufficientDiskSpace(requiredMinimumBytes, availableBytes, _) = reason else {
            return nil
        }
        return DiskSpaceAlertContext(
            requiredMinimumText: DownloadManifestItem.formatBytes(requiredMinimumBytes),
            availableText: DownloadManifestItem.formatBytes(availableBytes)
        )
    }

    func userFacingFailureMessage(for technicalMessage: String) -> String {
        if isMovePermissionFailure(technicalMessage) {
            return String(localized: "Nie udało się zapisać instalatora w lokalizacji docelowej. Sprawdź uprawnienia i spróbuj ponownie.")
        }
        return technicalMessage
    }

    func isMovePermissionFailure(_ message: String) -> Bool {
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

    func isInternetTimeoutFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("brak dostępu do internetu przez ponad 1 minutę")
            || normalized.contains("brak dostepu do internetu przez ponad 1 minute")
    }

    func runConnectionCheck(
        for entry: MacOSInstallerEntry,
        using logic: MacOSDownloaderLogic,
        diskImageConfiguration: MacOSDiskImageConfiguration,
        collisionDecision: @escaping @MainActor (MacOSDiskImageCollisionContext) -> Bool
    ) async throws -> DownloadManifest {
        currentStage = .connection
        connectionStatusText = String(localized: "Łączenie z serwerami Apple i pobieranie manifestu wybranego systemu...")

        let manifest = try await logic.prepareDownloadManifest(for: entry) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.connectionStatusText = status
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
                "Manifest systemu item: name=\(item.name), size=\(item.expectedSizeBytes), digest=\(digestPreview), url=\(item.url.absoluteString)",
                category: "Downloader"
            )
        }

        connectionStatusText = String(localized: "Sprawdzanie dostępnego miejsca w katalogu tymczasowym...")
        if diskImageConfiguration.isEnabled {
            let plan = try MacOSDiskImagePreflight().prepare(
                configuration: diskImageConfiguration,
                entry: entry,
                installerBytes: manifest.totalExpectedBytes
            )
            if let collisionContext = plan.collisionContext,
               !collisionDecision(collisionContext) {
                throw MacOSDiskImagePreflightCancelled()
            }
            activeDiskImagePreflightPlan = plan
        } else {
            try verifyTemporaryDiskCapacity(requiredBytes: manifest.totalExpectedBytes)
        }

        downloadTotal = manifest.items.count
        verifyTotal = manifest.items.count
        connectionStatusText = String(
            format: String(localized: "Wykryto %@ plików o łącznym rozmiarze %@..."),
            String(manifest.items.count),
            DownloadManifestItem.formatBytes(manifest.totalExpectedBytes)
        )
        completedStages.insert(.connection)
        return manifest
    }

    func formatDiskImageGigabytes(_ bytes: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let gigabytes = Double(bytes) / 1_000_000_000
        return formatter.string(from: NSNumber(value: gigabytes))
            ?? String(format: "%.2f", gigabytes)
    }

    func diskImageTechnicalDescription(for error: Error) -> String {
        switch error {
        case MacOSDiskImageCreationError.missingConfiguration:
            return "Missing disk image configuration"
        case MacOSDiskImageCreationError.missingInstaller:
            return "Missing source installer"
        case MacOSDiskImageCreationError.missingSessionOutput:
            return "Missing session output directory"
        case MacOSDiskImageCreationError.destinationUnavailable:
            return "Disk image destination is unavailable"
        case MacOSDiskImageCreationError.destinationCollision:
            return "Disk image destination collision occurred during finalization"
        case let MacOSDiskImageCreationError.stagingFailed(details):
            return details
        case let MacOSDiskImageCreationError.processFailed(details):
            return details
        case MacOSDiskImageCreationError.invalidOutput:
            return "hdiutil did not create a valid disk image"
        case let MacOSDiskImageCreationError.sourceRestoreFailed(details):
            return "Source installer restoration failed: \(details)"
        default:
            return error.localizedDescription
        }
    }
}
