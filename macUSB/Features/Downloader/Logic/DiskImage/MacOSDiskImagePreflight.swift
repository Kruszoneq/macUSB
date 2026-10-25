import Foundation

struct MacOSDiskImagePreflight {
    private let fileManager: FileManager
    private let workflow: AppLogging.Workflow

    init(fileManager: FileManager = .default, workflow: AppLogging.Workflow) {
        self.fileManager = fileManager
        self.workflow = workflow
    }

    func prepare(
        configuration: MacOSDiskImageConfiguration,
        entry: MacOSInstallerEntry,
        installerBytes: Int64
    ) throws -> MacOSDiskImagePreflightPlan {
        AppLogging.info(
            "DMG download space preflight started for \(entry.displayTitle).",
            stage: .downloader, workflow: workflow
        )
        guard configuration.isEnabled,
              let destinationDirectoryURL = configuration.destinationDirectoryURL
        else {
            AppLogging.error(
                "DMG download space preflight: active configuration or destination directory missing.",
                stage: .downloader, workflow: workflow
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
                "DMG download space preflight: destination directory unavailable or not writable: \(destinationURL.path).",
                stage: .downloader, workflow: workflow
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
                "DMG download space preflight: failed to read volume capacity: \(error.localizedDescription)",
                stage: .downloader, workflow: workflow
            )
            throw error
        }
        let systemRequiredBytes = scaledBytes(installerBytes, multiplier: 2.5)
        let diskImageRequiredBytes = scaledBytes(installerBytes, multiplier: 1.05)

        if systemVolume.identifier == destinationVolume.identifier {
            let combinedRequiredBytes = systemRequiredBytes + diskImageRequiredBytes
            logCapacityResult(
                location: "shared temporary and DMG volume",
                requiredBytes: combinedRequiredBytes,
                availableBytes: systemVolume.availableBytes,
                details: "temporary=\(MacOSDownloadDiskSpaceDiagnostics.describe(systemRequiredBytes)), DMG=\(MacOSDownloadDiskSpaceDiagnostics.describe(diskImageRequiredBytes))"
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
                location: "temporary directory volume",
                requiredBytes: systemRequiredBytes,
                availableBytes: systemVolume.availableBytes
            )
            logCapacityResult(
                location: "DMG destination volume",
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
            "DMG download space preflight passed; destination directory=\(destinationURL.path), planned file=\(resolvedURL.lastPathComponent).",
            stage: .downloader, workflow: workflow
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
        let detailSuffix = details.map { ", components=[\($0)]" } ?? ""
        AppLogging.info(
            "Download space preflight [\(location)]: required=\(MacOSDownloadDiskSpaceDiagnostics.describe(requiredBytes)), available=\(MacOSDownloadDiskSpaceDiagnostics.describe(availableBytes)), result=\(MacOSDownloadDiskSpaceDiagnostics.status(requiredBytes: requiredBytes, availableBytes: availableBytes))\(detailSuffix).",
            stage: .downloader, workflow: workflow
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
