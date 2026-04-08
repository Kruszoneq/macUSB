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
        buildStatusText = String(localized: "Przygotowywanie instalatora...")
        buildProgress = 0

        let assemblySelection = try resolveAssemblyInput(in: manifest)

        AppLogging.info(
            "Assembly workflow=\(assemblySelection.workflow.rawValue), input=\(assemblySelection.inputURL.lastPathComponent), entry=\(entry.name) \(entry.version)",
            category: "Downloader"
        )

        let finalAppURL: URL
        switch assemblySelection.workflow {
        case .legacy:
            finalAppURL = try await runLegacyAssemblyWithoutRoot(
                manifest: manifest,
                entry: entry
            )
        case .oldestDiskImage:
            finalAppURL = try await runOldestDiskImageAssemblyWithoutRoot(
                diskImageURL: assemblySelection.inputURL,
                entry: entry
            )
        case .modern:
            finalAppURL = try await runPackageAssemblyWithHelper(
                packageURL: assemblySelection.inputURL,
                entry: entry
            )
        }

        finalInstallerAppURL = finalAppURL
        buildStatusText = String(localized: "Instalator został przygotowany")
        buildProgress = 1.0
        completedStages.insert(.buildingInstaller)

        AppLogging.info(
            "Assembly success destination=\(finalAppURL.path)",
            category: "Downloader"
        )
    }

    func runPackageAssemblyWithHelper(
        packageURL: URL,
        entry: MacOSInstallerEntry
    ) async throws -> URL {
        guard let outputDirectory = activeSessionOutputURL else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "Brak katalogu output sesji"))
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
                result.errorMessage ?? String(localized: "Helper zwrócił błąd składania instalatora")
            )
        }
        guard let outputAppPath = result.outputAppPath else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "Helper nie zwrócił ścieżki do instalatora .app"))
        }

        let producedURL = URL(fileURLWithPath: outputAppPath)
        guard FileManager.default.fileExists(atPath: producedURL.path) else {
            throw DownloadFailureReason.assemblyFailed(String(localized: "Zbudowana aplikacja instalatora nie istnieje"))
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
                throw DownloadFailureReason.assemblyFailed(String(localized: "Nie znaleziono pobranego InstallAssistantAuto.pkg"))
            }
            return (url, .legacy)
        }

        if let modernItem = manifest.items.first(where: { item in
            item.name.caseInsensitiveCompare("InstallAssistant.pkg") == .orderedSame
                || item.url.lastPathComponent.caseInsensitiveCompare("InstallAssistant.pkg") == .orderedSame
        }) {
            guard let url = downloadedFileURLsByItemID[modernItem.id] else {
                throw DownloadFailureReason.assemblyFailed(String(localized: "Nie znaleziono pobranego InstallAssistant.pkg"))
            }
            return (url, .modern)
        }

        if let oldestDiskImageItem = manifest.items.first(where: { item in
            item.url.pathExtension.caseInsensitiveCompare("dmg") == .orderedSame
                || item.name.lowercased().hasSuffix(".dmg")
        }) {
            guard let url = downloadedFileURLsByItemID[oldestDiskImageItem.id] else {
                throw DownloadFailureReason.assemblyFailed(String(localized: "Nie znaleziono pobranego obrazu .dmg"))
            }
            return (url, .oldestDiskImage)
        }

        throw DownloadFailureReason.assemblyFailed(
            String(localized: "Nie znaleziono pliku instalatora dla wybranego systemu (wymagany InstallAssistant.pkg, InstallAssistantAuto.pkg lub obraz .dmg)")
        )
    }
}
