import Foundation

struct MacOSDiskImageConfiguration: Equatable {
    let isEnabled: Bool
    let destinationDirectoryURL: URL?

    nonisolated static let disabled = MacOSDiskImageConfiguration(
        isEnabled: false,
        destinationDirectoryURL: nil
    )
}

enum MacOSDiskImageSpaceLocation: Equatable {
    case systemVolume
    case destinationVolume
}

struct MacOSDiskImageCollisionContext: Equatable {
    let directoryURL: URL
    let existingFileName: String
    let proposedFileName: String
}

struct MacOSDiskImagePreflightPlan: Equatable {
    let destinationDirectoryURL: URL
    let destinationURL: URL
    let volumeName: String
    let collisionContext: MacOSDiskImageCollisionContext?
}

enum MacOSDiskImagePreflightError: Error, Equatable {
    case destinationUnavailable
    case capacityUnavailable
    case insufficientSpace(
        location: MacOSDiskImageSpaceLocation,
        requiredBytes: Int64,
        availableBytes: Int64
    )
}

enum MacOSDiskImageCreationOutcome: Equatable {
    case success(diskImageURL: URL)
    case partialSuccess(diskImageURL: URL, retainedInstallerURL: URL)
}

enum MacOSDiskImageCreationError: Error {
    case missingConfiguration
    case missingInstaller
    case missingSessionOutput
    case destinationUnavailable
    case destinationCollision
    case stagingFailed(String)
    case processFailed(String)
    case invalidOutput
    case sourceRestoreFailed(String)
}
