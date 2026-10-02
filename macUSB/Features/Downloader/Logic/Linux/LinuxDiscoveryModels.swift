import Foundation

enum LinuxDistribution: String, CaseIterable, Hashable {
    case ubuntu
    case debian
    case linuxMint
    case proxmoxVirtualEnvironment
    case proxmoxBackupServer
    case nixos
    case cachyos

    var displayName: String {
        switch self {
        case .ubuntu:
            return "Ubuntu"
        case .debian:
            return "Debian"
        case .linuxMint:
            return "Linux Mint"
        case .proxmoxVirtualEnvironment:
            return "Proxmox VE"
        case .proxmoxBackupServer:
            return "Proxmox Backup Server"
        case .nixos:
            return "NixOS"
        case .cachyos:
            return "CachyOS"
        }
    }

    /// Name of the distro icon in `Resources/Icons/Linux/Distros`, shared with Linux analysis.
    var iconResourceName: String {
        switch self {
        case .ubuntu:
            return "ubuntu"
        case .debian:
            return "debian"
        case .linuxMint:
            return "mint"
        case .nixos:
            return "nixos"
        case .proxmoxVirtualEnvironment, .proxmoxBackupServer, .cachyos:
            return "linux"
        }
    }
}

enum LinuxImageArchitecture: String, Hashable {
    case x86_64
    case arm64

    var displayName: String {
        switch self {
        case .x86_64:
            return "x86_64"
        case .arm64:
            return "ARM64"
        }
    }
}

struct LinuxImageEntry: Identifiable, Hashable {
    let distribution: LinuxDistribution
    let edition: String
    let version: String
    let isLongTermSupport: Bool
    let architecture: LinuxImageArchitecture
    let fileName: String
    let downloadURL: URL
    let checksumSourceURL: URL
    let expectedSHA256: String
    var sizeBytes: Int64?
    var isDownloaded: Bool = false

    var id: String { downloadURL.absoluteString }

    var title: String {
        let base = "\(distribution.displayName) \(version)"
        return edition.isEmpty ? base : "\(base) \(edition)"
    }

    /// Entries sharing this key are versions of the same image line; the default list shows the newest one.
    var lineKey: String {
        [
            distribution.rawValue,
            edition,
            architecture.rawValue,
            isLongTermSupport ? "lts" : "regular"
        ].joined(separator: "|")
    }

    var sizeText: String? {
        guard let sizeBytes, sizeBytes > 0 else { return nil }
        return DownloadManifestItem.formatBytes(sizeBytes)
    }
}

struct LinuxDistributionGroup: Identifiable, Hashable {
    let distribution: LinuxDistribution
    let entries: [LinuxImageEntry]

    var id: String { distribution.rawValue }
}

/// One network source; a single index can describe several distributions (Proxmox VE and Backup Server).
enum LinuxDiscoverySource: String, CaseIterable {
    case ubuntu
    case debian
    case linuxMint
    case proxmox
    case nixos
    case cachyos

    var distributions: [LinuxDistribution] {
        switch self {
        case .ubuntu:
            return [.ubuntu]
        case .debian:
            return [.debian]
        case .linuxMint:
            return [.linuxMint]
        case .proxmox:
            return [.proxmoxVirtualEnvironment, .proxmoxBackupServer]
        case .nixos:
            return [.nixos]
        case .cachyos:
            return [.cachyos]
        }
    }

    var displayName: String {
        switch self {
        case .proxmox:
            return "Proxmox"
        default:
            return distributions.first?.displayName ?? rawValue
        }
    }
}

enum LinuxDiscoveryError: LocalizedError {
    case invalidResponse(URL, Int)
    case unreadableContent(URL)
    case noImagesFound(LinuxDiscoverySource)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(url, statusCode):
            return "HTTP \(statusCode) for \(url.absoluteString)"
        case let .unreadableContent(url):
            return "Unreadable content at \(url.absoluteString)"
        case let .noImagesFound(source):
            return "No images found for \(source.rawValue)"
        }
    }
}
