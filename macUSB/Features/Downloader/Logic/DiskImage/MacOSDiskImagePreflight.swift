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
        guard configuration.isEnabled,
              let destinationDirectoryURL = configuration.destinationDirectoryURL
        else {
            throw MacOSDiskImagePreflightError.destinationUnavailable
        }

        let destinationURL = destinationDirectoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isWritableFile(atPath: destinationURL.path)
        else {
            throw MacOSDiskImagePreflightError.destinationUnavailable
        }

        let systemVolume = try volumeSnapshot(for: fileManager.temporaryDirectory)
        let destinationVolume = try volumeSnapshot(for: destinationURL)
        let systemRequiredBytes = scaledBytes(installerBytes, multiplier: 2.5)
        let diskImageRequiredBytes = scaledBytes(installerBytes, multiplier: 1.05)

        if systemVolume.identifier == destinationVolume.identifier {
            let combinedRequiredBytes = systemRequiredBytes + diskImageRequiredBytes
            guard systemVolume.availableBytes >= combinedRequiredBytes else {
                throw MacOSDiskImagePreflightError.insufficientSpace(
                    location: .systemVolume,
                    requiredBytes: combinedRequiredBytes,
                    availableBytes: systemVolume.availableBytes
                )
            }
        } else {
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

        return MacOSDiskImagePreflightPlan(
            destinationDirectoryURL: destinationURL,
            destinationURL: resolvedURL,
            volumeName: MacOSDiskImageNamingPolicy.baseName(for: entry),
            collisionContext: collisionContext
        )
    }

    private func scaledBytes(_ bytes: Int64, multiplier: Double) -> Int64 {
        Int64((Double(bytes) * multiplier).rounded(.up))
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
