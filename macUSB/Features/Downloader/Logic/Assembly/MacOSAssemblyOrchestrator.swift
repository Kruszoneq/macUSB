import Foundation
import Darwin

extension MontereyDownloadFlowModel {
    private enum InstallerDistributionWorkflow: String {
        case modern = "Modern"
        case legacy = "Legacy"
        case oldestDiskImage = "OldestDiskImage"
    }

    func runInstallerBuild(
        manifest: DownloadManifest,
        entry: MacOSInstallerEntry
    ) async throws {
        currentStage = .buildingInstaller
        buildStatusText = String(localized: "downloader.assembly.status.preparing_installer", table: "Downloader")
        buildProgress = 0

        let assemblySelection = try resolveAssemblyInput(in: manifest)

        AppLogging.info(
            "Assembly workflow=\(assemblySelection.workflow.rawValue), input=\(assemblySelection.inputURL.lastPathComponent), entry=\(entry.name) \(entry.version)",
            stage: .downloader, workflow: loggingWorkflow
        )

        let finalAppURL: URL
        switch assemblySelection.workflow {
        case .legacy:
            finalAppURL = try await runLegacyAssemblyWithoutRoot(
                manifest: manifest,
                entry: entry
            )
        case .oldestDiskImage:
            if isInstallerBasedOldestEntry(entry) {
                finalAppURL = try await runInstallerBasedOldestDiskImageAssemblyWithHelper(
                    diskImageURL: assemblySelection.inputURL,
                    entry: entry
                )
            } else {
                finalAppURL = try await runOldestDiskImageAssemblyWithoutRoot(
                    diskImageURL: assemblySelection.inputURL,
                    entry: entry
                )
            }
        case .modern:
            finalAppURL = try await runPackageAssemblyWithHelper(
                packageURL: assemblySelection.inputURL,
                entry: entry
            )
        }

        finalInstallerAppURL = finalAppURL
        buildStatusText = String(localized: "downloader.assembly.status.installer_prepared", table: "Downloader")
        buildProgress = 1.0
        completedStages.insert(.buildingInstaller)

        AppLogging.info(
            "Assembly success destination=\(finalAppURL.path)",
            stage: .downloader, workflow: loggingWorkflow
        )
    }

    private func isInstallerBasedOldestEntry(_ entry: MacOSInstallerEntry) -> Bool {
        if entry.version.hasPrefix("10.10")
            || entry.version.hasPrefix("10.11")
            || entry.version.hasPrefix("10.12") {
            return true
        }
        let normalizedName = entry.name.lowercased()
        if normalizedName.contains("high sierra") {
            return false
        }
        return normalizedName.contains("yosemite")
            || normalizedName.contains("el capitan")
            || normalizedName.contains("sierra")
    }

    func runInstallerBasedOldestDiskImageAssemblyWithHelper(
        diskImageURL: URL,
        entry: MacOSInstallerEntry
    ) async throws -> URL {
        guard let outputDirectory = activeSessionOutputURL else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.missing_output_directory", table: "Downloader"))
        }
        let request = DownloaderAssemblyRequestPayload(
            packagePath: diskImageURL.path,
            outputDirectoryPath: outputDirectory.path,
            expectedAppName: expectedInstallerAppName(for: entry),
            finalDestinationDirectoryPath: "",
            cleanupSessionFiles: false,
            requesterUID: getuid(),
            patchLegacyDistributionInDebug: false
        )
        cleanupDelegatedToHelper = request.cleanupSessionFiles

        let result = try await startAssemblyWithHelper(request: request)
        if result.cleanupRequested && result.cleanupSucceeded {
            sessionCleanupHandledByHelper = true
            helperCleanupFailureMessage = nil
            activeSessionRootURL = nil
            activeSessionPayloadURL = nil
            activeSessionOutputURL = nil
        } else if result.cleanupRequested {
            sessionCleanupHandledByHelper = false
            helperCleanupFailureMessage = result.cleanupErrorMessage
        } else {
            sessionCleanupHandledByHelper = false
            helperCleanupFailureMessage = nil
        }

        guard result.success else {
            throw DownloadFailureReason.assemblyFailed(
                result.errorMessage ?? String(localized: "downloader.assembly.error.helper_failed", table: "Downloader")
            )
        }
        guard let outputAppPath = result.outputAppPath else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.helper_missing_installer_path", table: "Downloader"))
        }

        let producedURL = URL(fileURLWithPath: outputAppPath)
        guard FileManager.default.fileExists(atPath: producedURL.path) else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.installer_missing", table: "Downloader"))
        }
        return producedURL
    }

    func runPackageAssemblyWithHelper(
        packageURL: URL,
        entry: MacOSInstallerEntry
    ) async throws -> URL {
        guard let outputDirectory = activeSessionOutputURL else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.missing_output_directory", table: "Downloader"))
        }
        let request = DownloaderAssemblyRequestPayload(
            packagePath: packageURL.path,
            outputDirectoryPath: outputDirectory.path,
            expectedAppName: expectedInstallerAppName(for: entry),
            finalDestinationDirectoryPath: "",
            cleanupSessionFiles: false,
            requesterUID: getuid(),
            patchLegacyDistributionInDebug: false
        )
        cleanupDelegatedToHelper = request.cleanupSessionFiles

        let result = try await startAssemblyWithHelper(request: request)
        if result.cleanupRequested && result.cleanupSucceeded {
            sessionCleanupHandledByHelper = true
            helperCleanupFailureMessage = nil
            activeSessionRootURL = nil
            activeSessionPayloadURL = nil
            activeSessionOutputURL = nil
        } else if result.cleanupRequested {
            sessionCleanupHandledByHelper = false
            helperCleanupFailureMessage = result.cleanupErrorMessage
        } else {
            sessionCleanupHandledByHelper = false
            helperCleanupFailureMessage = nil
        }

        guard result.success else {
            throw DownloadFailureReason.assemblyFailed(
                result.errorMessage ?? String(localized: "downloader.assembly.error.helper_failed", table: "Downloader")
            )
        }
        guard let outputAppPath = result.outputAppPath else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.helper_missing_installer_path", table: "Downloader"))
        }

        let producedURL = URL(fileURLWithPath: outputAppPath)
        guard FileManager.default.fileExists(atPath: producedURL.path) else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.installer_missing", table: "Downloader"))
        }
        return producedURL
    }

    func expectedInstallerAppName(for entry: MacOSInstallerEntry) -> String {
        let normalized = entry.name.replacingOccurrences(
            of: #"^(Install\s+)?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let baseName = normalized.isEmpty ? "macOS \(entry.version)" : normalized
        return "Install \(baseName).app"
    }

    private func resolveAssemblyInput(
        in manifest: DownloadManifest
    ) throws -> (inputURL: URL, workflow: InstallerDistributionWorkflow) {
        if let legacyItem = manifest.items.first(where: { item in
            item.name.caseInsensitiveCompare("InstallAssistantAuto.pkg") == .orderedSame
                || item.url.lastPathComponent.caseInsensitiveCompare("InstallAssistantAuto.pkg") == .orderedSame
        }) {
            guard let url = downloadedFileURLsByItemID[legacyItem.id] else {
                throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.missing_install_assistant_auto", table: "Downloader"))
            }
            return (url, .legacy)
        }

        if let modernItem = manifest.items.first(where: { item in
            item.name.caseInsensitiveCompare("InstallAssistant.pkg") == .orderedSame
                || item.url.lastPathComponent.caseInsensitiveCompare("InstallAssistant.pkg") == .orderedSame
        }) {
            guard let url = downloadedFileURLsByItemID[modernItem.id] else {
                throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.missing_install_assistant", table: "Downloader"))
            }
            return (url, .modern)
        }

        if let oldestDiskImageItem = manifest.items.first(where: { item in
            item.url.pathExtension.caseInsensitiveCompare("dmg") == .orderedSame
                || item.name.lowercased().hasSuffix(".dmg")
        }) {
            guard let url = downloadedFileURLsByItemID[oldestDiskImageItem.id] else {
                throw DownloadFailureReason.assemblyFailed(String(localized: "downloader.assembly.error.missing_downloaded_image", table: "Downloader"))
            }
            return (url, .oldestDiskImage)
        }

        throw DownloadFailureReason.assemblyFailed(
            String(localized: "downloader.assembly.error.missing_installer_payload", table: "Downloader")
        )
    }
}
