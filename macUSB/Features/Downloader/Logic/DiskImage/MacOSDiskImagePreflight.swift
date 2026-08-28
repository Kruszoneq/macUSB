import Foundation

struct MacOSDiskImagePreflight {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepare(
        configuration: MacOSDiskImageConfiguration,
        entry: MacOSInstallerEntry,
        installerBytes: Int64
    ) throws -> MacOSDiskImagePreflightPlan {
        AppLogging.info(
            "Preflight miejsca przed pobieraniem z obrazem DMG: rozpoczęcie dla \(entry.displayTitle).",
            category: "Downloader"
        )
        guard configuration.isEnabled,
              let destinationDirectoryURL = configuration.destinationDirectoryURL
        else {
            AppLogging.error(
                "Preflight miejsca przed pobieraniem z obrazem DMG: brak aktywnej konfiguracji lub katalogu docelowego.",
                category: "Downloader"
            )
            throw MacOSDiskImagePreflightError.destinationUnavailable
        }

        let destinationURL = destinationDirectoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isWritableFile(atPath: destinationURL.path)
        else {
            AppLogging.error(
                "Preflight miejsca przed pobieraniem z obrazem DMG: katalog docelowy jest niedostępny lub niezapisywalny: \(destinationURL.path).",
                category: "Downloader"
            )
            throw MacOSDiskImagePreflightError.destinationUnavailable
        }

        let systemVolume: VolumeSnapshot
        let destinationVolume: VolumeSnapshot
        do {
            systemVolume = try volumeSnapshot(for: fileManager.temporaryDirectory)
            destinationVolume = try volumeSnapshot(for: destinationURL)
        } catch {
            AppLogging.error(
                "Preflight miejsca przed pobieraniem z obrazem DMG: nie udało się odczytać pojemności woluminu: \(error.localizedDescription)",
                category: "Downloader"
            )
            throw error
        }
        let systemRequiredBytes = scaledBytes(installerBytes, multiplier: 2.5)
        let diskImageRequiredBytes = scaledBytes(installerBytes, multiplier: 1.05)

        if systemVolume.identifier == destinationVolume.identifier {
            let combinedRequiredBytes = systemRequiredBytes + diskImageRequiredBytes
            logCapacityResult(
                location: "wspólny wolumin katalogu tymczasowego i obrazu DMG",
                requiredBytes: combinedRequiredBytes,
                availableBytes: systemVolume.availableBytes,
                details: "tymczasowe=\(MacOSDownloadDiskSpaceDiagnostics.describe(systemRequiredBytes)), DMG=\(MacOSDownloadDiskSpaceDiagnostics.describe(diskImageRequiredBytes))"
            )
            guard systemVolume.availableBytes >= combinedRequiredBytes else {
                throw MacOSDiskImagePreflightError.insufficientSpace(
                    location: .systemVolume,
                    requiredBytes: combinedRequiredBytes,
                    availableBytes: systemVolume.availableBytes
                )
            }
        } else {
            logCapacityResult(
                location: "wolumin katalogu tymczasowego",
                requiredBytes: systemRequiredBytes,
                availableBytes: systemVolume.availableBytes
            )
            logCapacityResult(
                location: "wolumin docelowy obrazu DMG",
                requiredBytes: diskImageRequiredBytes,
                availableBytes: destinationVolume.availableBytes
            )
            guard systemVolume.availableBytes >= systemRequiredBytes else {
                throw MacOSDiskImagePreflightError.insufficientSpace(
                    location: .systemVolume,
                    requiredBytes: systemRequiredBytes,
                    availableBytes: systemVolume.availableBytes
                )
            }
            guard destinationVolume.availableBytes >= diskImageRequiredBytes else {
                throw MacOSDiskImagePreflightError.insufficientSpace(
                    location: .destinationVolume,
                    requiredBytes: diskImageRequiredBytes,
                    availableBytes: destinationVolume.availableBytes
                )
            }
        }

        let preferredFileName = MacOSDiskImageNamingPolicy.preferredFileName(for: entry)
        let preferredURL = destinationURL.appendingPathComponent(preferredFileName)
        let resolvedURL = MacOSDiskImageNamingPolicy.firstAvailableURL(
            in: destinationURL,
            preferredFileName: preferredFileName,
            fileManager: fileManager
        )
        let collisionContext: MacOSDiskImageCollisionContext?
        if preferredURL != resolvedURL {
            collisionContext = MacOSDiskImageCollisionContext(
                directoryURL: destinationURL,
                existingFileName: preferredFileName,
                proposedFileName: resolvedURL.lastPathComponent
            )
        } else {
            collisionContext = nil
        }

        AppLogging.info(
            "Preflight miejsca przed pobieraniem z obrazem DMG: zakończono pomyślnie; katalog docelowy=\(destinationURL.path), planowany plik=\(resolvedURL.lastPathComponent).",
            category: "Downloader"
        )

        return MacOSDiskImagePreflightPlan(
            destinationDirectoryURL: destinationURL,
            preferredFileName: preferredFileName,
            destinationURL: resolvedURL,
            volumeName: MacOSDiskImageNamingPolicy.baseName(for: entry),
            collisionContext: collisionContext
        )
    }

    private func scaledBytes(_ bytes: Int64, multiplier: Double) -> Int64 {
        Int64((Double(bytes) * multiplier).rounded(.up))
    }

    private func logCapacityResult(
        location: String,
        requiredBytes: Int64,
        availableBytes: Int64,
        details: String? = nil
    ) {
        let detailSuffix = details.map { ", składniki=[\($0)]" } ?? ""
        AppLogging.info(
            "Preflight miejsca przed pobieraniem [\(location)]: wymagane=\(MacOSDownloadDiskSpaceDiagnostics.describe(requiredBytes)), dostępne=\(MacOSDownloadDiskSpaceDiagnostics.describe(availableBytes)), wynik=\(MacOSDownloadDiskSpaceDiagnostics.status(requiredBytes: requiredBytes, availableBytes: availableBytes))\(detailSuffix).",
            category: "Downloader"
        )
    }

    private func volumeSnapshot(for url: URL) throws -> VolumeSnapshot {
        let values = try url.resourceValues(forKeys: [
            .volumeIdentifierKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        guard let identifier = values.volumeIdentifier,
              let availableCapacity = values.volumeAvailableCapacityForImportantUsage
        else {
            throw MacOSDiskImagePreflightError.capacityUnavailable
        }
        return VolumeSnapshot(
            identifier: String(describing: identifier),
            availableBytes: Int64(availableCapacity)
        )
    }

    private struct VolumeSnapshot {
        let identifier: String
        let availableBytes: Int64
    }
}
