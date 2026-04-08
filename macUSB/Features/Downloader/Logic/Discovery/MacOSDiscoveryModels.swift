import Foundation

struct MacOSInstallerEntry: Identifiable, Hashable {
    let id: String
    let family: String
    let name: String
    let version: String
    let build: String
    let installerSizeText: String?
    let sourceURL: URL
    let catalogProductID: String?

    var displayTitle: String {
        "\(name) \(version) (\(build))"
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
            catalogProductID: catalogProductID
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
