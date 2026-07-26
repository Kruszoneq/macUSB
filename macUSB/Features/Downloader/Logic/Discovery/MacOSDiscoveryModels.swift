import Foundation

enum MacOSInstallerReleaseChannel: String, Hashable, Sendable {
    case stable
    case publicBeta

    var sortPriority: Int {
        switch self {
        case .stable:
            return 0
        case .publicBeta:
            return 1
        }
    }
}

struct MacOSInstallerEntry: Identifiable, Hashable {
    let id: String
    let family: String
    let name: String
    let version: String
    let build: String
    let installerSizeText: String?
    let sourceURL: URL
    let catalogProductID: String?
    let releaseChannel: MacOSInstallerReleaseChannel
    let catalogURL: URL?

    var isBeta: Bool {
        releaseChannel == .publicBeta
    }

    var displayTitle: String {
        "\(family) \(version) (\(build))"
    }

    func with(installerSizeText: String?) -> MacOSInstallerEntry {
        MacOSInstallerEntry(
            id: id,
            family: family,
            name: name,
            version: version,
            build: build,
            installerSizeText: installerSizeText,
            sourceURL: sourceURL,
            catalogProductID: catalogProductID,
            releaseChannel: releaseChannel,
            catalogURL: catalogURL
        )
    }
}

struct MacOSInstallerFamilyGroup: Identifiable, Hashable {
    let family: String
    let entries: [MacOSInstallerEntry]

    var id: String { family }
}

enum DownloaderDiscoveryState: Equatable {
    case idle
    case loading
    case loaded
    case failed
    case cancelled
}
