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
    let isDownloaded: Bool

    init(
        id: String,
        family: String,
        name: String,
        version: String,
        build: String,
        installerSizeText: String?,
        sourceURL: URL,
        catalogProductID: String?,
        releaseChannel: MacOSInstallerReleaseChannel,
        catalogURL: URL?,
        isDownloaded: Bool = false
    ) {
        self.id = id
        self.family = family
        self.name = name
        self.version = version
        self.build = build
        self.installerSizeText = installerSizeText
        self.sourceURL = sourceURL
        self.catalogProductID = catalogProductID
        self.releaseChannel = releaseChannel
        self.catalogURL = catalogURL
        self.isDownloaded = isDownloaded
    }

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
            catalogURL: catalogURL,
            isDownloaded: isDownloaded
        )
    }

    func with(isDownloaded: Bool) -> MacOSInstallerEntry {
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
            catalogURL: catalogURL,
            isDownloaded: isDownloaded
        )
    }
}

struct MacOSInstallerDiscoveryResult {
    let entries: [MacOSInstallerEntry]
    let unrecognizedLocalInstallerCount: Int
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
