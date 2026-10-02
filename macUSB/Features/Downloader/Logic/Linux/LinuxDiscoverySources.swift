import Foundation

/// Reads official distribution indexes and returns entries with their published SHA-256 values.
struct LinuxDiscoverySources {
    let session: URLSession

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }

    func entries(for source: LinuxDiscoverySource) async throws -> [LinuxImageEntry] {
        let entries: [LinuxImageEntry]
        switch source {
        case .ubuntu:
            entries = try await ubuntuEntries()
        case .debian:
            entries = try await debianEntries()
        case .linuxMint:
            entries = try await linuxMintEntries()
        case .proxmox:
            entries = try await proxmoxEntries()
        case .nixos:
            entries = try await nixosEntries()
        case .cachyos:
            entries = try await cachyosEntries()
        }
        guard !entries.isEmpty else {
            throw LinuxDiscoveryError.noImagesFound(source)
        }
        return entries
    }

    // MARK: - Ubuntu

    private struct UbuntuRelease {
        let versionPath: String
        let isLongTermSupport: Bool
    }

    private func ubuntuEntries() async throws -> [LinuxImageEntry] {
        let metaReleaseURL = URL(string: "https://changelogs.ubuntu.com/meta-release")!
        let releases = ubuntuReleasesInStandardSupport(
            metaRelease: try await fetchText(metaReleaseURL)
        )

        var entries: [LinuxImageEntry] = []
        for release in releases {
            try Task.checkCancellation()
            let checksumLists = [
                URL(string: "https://releases.ubuntu.com/\(release.versionPath)/")!,
                URL(string: "https://cdimage.ubuntu.com/releases/\(release.versionPath)/release/")!
            ]
            for directoryURL in checksumLists {
                let checksumURL = directoryURL.appendingPathComponent("SHA256SUMS")
                let lines: [LinuxDiscoveryParsing.ChecksumLine]
                do {
                    lines = LinuxDiscoveryParsing.checksumLines(from: try await fetchText(checksumURL))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    AppLogging.info(
                        "Linux discovery skipped Ubuntu checksum list \(checksumURL.absoluteString): \(error.localizedDescription)",
                        stage: .downloader, workflow: .discovery
                    )
                    continue
                }

                let releaseEntries = lines.compactMap { line -> LinuxImageEntry? in
                    guard let groups = LinuxDiscoveryParsing.captures(
                        in: line.fileName,
                        pattern: #"ubuntu-(\d+\.\d+(?:\.\d+)?)-(desktop|live-server)-(amd64|arm64)\.iso"#
                    ) else { return nil }
                    let version = groups[0]
                    let edition = groups[1] == "desktop" ? "Desktop" : "Server"
                    let architecture: LinuxImageArchitecture = groups[2] == "arm64" ? .arm64 : .x86_64
                    return LinuxImageEntry(
                        distribution: .ubuntu,
                        edition: edition,
                        version: release.isLongTermSupport ? "\(version) LTS" : version,
                        isLongTermSupport: release.isLongTermSupport,
                        architecture: architecture,
                        fileName: line.fileName,
                        downloadURL: directoryURL.appendingPathComponent(line.fileName),
                        checksumSourceURL: checksumURL,
                        expectedSHA256: line.sha256
                    )
                }
                // Each release directory also lists older point releases; keep the newest one.
                entries.append(contentsOf: LinuxDiscoveryParsing.newestPerLine(releaseEntries))
            }
        }
        return entries
    }

    /// Supported releases from meta-release, limited to the five-year standard support window for LTS releases.
    private func ubuntuReleasesInStandardSupport(metaRelease: String) -> [UbuntuRelease] {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, dd MMMM yyyy HH:mm:ss zzz"
        let standardSupportCutoff = Calendar(identifier: .gregorian)
            .date(byAdding: .year, value: -5, to: Date()) ?? .distantPast

        return metaRelease
            .components(separatedBy: "\n\n")
            .compactMap { block -> UbuntuRelease? in
                var fields: [String: String] = [:]
                for line in block.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    fields[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces)
                }
                guard
                    fields["Supported"] == "1",
                    let version = fields["Version"],
                    let versionPath = LinuxDiscoveryParsing.captures(
                        in: version,
                        pattern: #"(\d+\.\d+)(?:\.\d+)?(?: LTS)?"#
                    )?.first
                else { return nil }

                let isLongTermSupport = version.hasSuffix("LTS")
                if isLongTermSupport,
                   let dateText = fields["Date"],
                   let releaseDate = dateFormatter.date(from: dateText),
                   releaseDate < standardSupportCutoff {
                    return nil
                }
                return UbuntuRelease(versionPath: versionPath, isLongTermSupport: isLongTermSupport)
            }
    }

    // MARK: - Debian

    private func debianEntries() async throws -> [LinuxImageEntry] {
        var entries: [LinuxImageEntry] = []
        for (archPath, architecture) in [("amd64", LinuxImageArchitecture.x86_64), ("arm64", .arm64)] {
            let directoryURL = URL(string: "https://cdimage.debian.org/debian-cd/current/\(archPath)/iso-cd/")!
            let checksumURL = directoryURL.appendingPathComponent("SHA256SUMS")
            let lines = LinuxDiscoveryParsing.checksumLines(from: try await fetchText(checksumURL))
            entries += lines.compactMap { line in
                guard let groups = LinuxDiscoveryParsing.captures(
                    in: line.fileName,
                    pattern: #"debian-(\d+(?:\.\d+)*)-\#(archPath)-netinst\.iso"#
                ) else { return nil }
                return LinuxImageEntry(
                    distribution: .debian,
                    edition: "netinst",
                    version: groups[0],
                    isLongTermSupport: false,
                    architecture: architecture,
                    fileName: line.fileName,
                    downloadURL: directoryURL.appendingPathComponent(line.fileName),
                    checksumSourceURL: checksumURL,
                    expectedSHA256: line.sha256
                )
            }
        }
        return entries
    }

    // MARK: - Linux Mint

    private func linuxMintEntries() async throws -> [LinuxImageEntry] {
        let indexURL = URL(string: "https://pub.linuxmint.io/stable/")!
        let versions = LinuxDiscoveryParsing.directoryNames(
            fromIndexHTML: try await fetchText(indexURL),
            matching: #"\d+(?:\.\d+)?"#
        )
        guard let newestVersion = LinuxDiscoveryParsing.newestVersion(in: versions) else {
            throw LinuxDiscoveryError.unreadableContent(indexURL)
        }

        let directoryURL = indexURL.appendingPathComponent(newestVersion, isDirectory: true)
        let checksumURL = directoryURL.appendingPathComponent("sha256sum.txt")
        let lines = LinuxDiscoveryParsing.checksumLines(from: try await fetchText(checksumURL))
        let editionNames = ["cinnamon": "Cinnamon", "mate": "MATE", "xfce": "Xfce"]
        return lines.compactMap { line in
            guard
                let groups = LinuxDiscoveryParsing.captures(
                    in: line.fileName,
                    pattern: #"linuxmint-(\d+(?:\.\d+)?)-(cinnamon|mate|xfce)-64bit\.iso"#
                ),
                let edition = editionNames[groups[1]]
            else { return nil }
            return LinuxImageEntry(
                distribution: .linuxMint,
                edition: edition,
                version: groups[0],
                isLongTermSupport: false,
                architecture: .x86_64,
                fileName: line.fileName,
                downloadURL: directoryURL.appendingPathComponent(line.fileName),
                checksumSourceURL: checksumURL,
                expectedSHA256: line.sha256
            )
        }
    }

    // MARK: - Proxmox

    private func proxmoxEntries() async throws -> [LinuxImageEntry] {
        let directoryURL = URL(string: "https://enterprise.proxmox.com/iso/")!
        let checksumURL = directoryURL.appendingPathComponent("SHA256SUMS")
        let lines = LinuxDiscoveryParsing.checksumLines(from: try await fetchText(checksumURL))
        let products: [(prefix: String, distribution: LinuxDistribution)] = [
            ("proxmox-ve", .proxmoxVirtualEnvironment),
            ("proxmox-backup-server", .proxmoxBackupServer)
        ]

        return lines.compactMap { line in
            for product in products {
                guard let groups = LinuxDiscoveryParsing.captures(
                    in: line.fileName,
                    pattern: #"\#(product.prefix)_(\d+\.\d+-\d+)(-arm64)?\.iso"#
                ) else { continue }
                return LinuxImageEntry(
                    distribution: product.distribution,
                    edition: "",
                    version: groups[0],
                    isLongTermSupport: false,
                    architecture: groups[1].isEmpty ? .x86_64 : .arm64,
                    fileName: line.fileName,
                    downloadURL: directoryURL.appendingPathComponent(line.fileName),
                    checksumSourceURL: checksumURL,
                    expectedSHA256: line.sha256
                )
            }
            return nil
        }
    }

    // MARK: - NixOS

    private func nixosEntries() async throws -> [LinuxImageEntry] {
        // Stable channels are YY.05 and YY.11; a channel branches off before its release,
        // so it is only considered once the release month has ended.
        for channel in nixosStableChannelCandidates() {
            try Task.checkCancellation()
            var entries: [LinuxImageEntry] = []
            for edition in ["graphical", "minimal"] {
                for (archName, architecture) in [("x86_64", LinuxImageArchitecture.x86_64), ("aarch64", .arm64)] {
                    let checksumURL = URL(
                        string: "https://channels.nixos.org/nixos-\(channel)/latest-nixos-\(edition)-\(archName)-linux.iso.sha256"
                    )!
                    let text: String
                    do {
                        text = try await fetchText(checksumURL)
                    } catch LinuxDiscoveryError.invalidResponse(_, 404) {
                        continue
                    }
                    guard
                        let line = LinuxDiscoveryParsing.checksumLines(from: text).first,
                        let groups = LinuxDiscoveryParsing.captures(
                            in: line.fileName,
                            pattern: #"nixos-\#(edition)-(\#(channel)\.[0-9a-z.]+)-\#(archName)-linux\.iso"#
                        )
                    else {
                        throw LinuxDiscoveryError.unreadableContent(checksumURL)
                    }
                    let downloadURL = URL(
                        string: "https://releases.nixos.org/nixos/\(channel)/nixos-\(groups[0])/\(line.fileName)"
                    )!
                    entries.append(
                        LinuxImageEntry(
                            distribution: .nixos,
                            edition: edition == "graphical" ? "Graphical" : "Minimal",
                            version: channel,
                            isLongTermSupport: false,
                            architecture: architecture,
                            fileName: line.fileName,
                            downloadURL: downloadURL,
                            checksumSourceURL: checksumURL,
                            expectedSHA256: line.sha256
                        )
                    )
                }
            }
            if !entries.isEmpty {
                return entries
            }
        }
        return []
    }

    private func nixosStableChannelCandidates() -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        var candidates: [String] = []
        for year in stride(from: currentYear, through: currentYear - 1, by: -1) {
            for month in [11, 5] {
                guard
                    let releaseMonthEnd = calendar.date(from: DateComponents(year: year, month: month + 1, day: 1)),
                    releaseMonthEnd <= now
                else { continue }
                candidates.append(String(format: "%02d.%02d", year % 100, month))
            }
        }
        return candidates
    }

    // MARK: - CachyOS

    private func cachyosEntries() async throws -> [LinuxImageEntry] {
        var entries: [LinuxImageEntry] = []
        for (editionPath, edition) in [("desktop", "Desktop"), ("handheld", "Handheld")] {
            let indexURL = URL(string: "https://us.cachyos.org/ISO/\(editionPath)/")!
            let releases = LinuxDiscoveryParsing.directoryNames(
                fromIndexHTML: try await fetchText(indexURL),
                matching: #"\d{6}"#
            )
            guard let release = LinuxDiscoveryParsing.newestVersion(in: releases) else {
                throw LinuxDiscoveryError.unreadableContent(indexURL)
            }

            let fileName = "cachyos-\(editionPath)-linux-\(release).iso"
            let directoryURL = URL(string: "https://cdn77.cachyos.org/ISO/\(editionPath)/\(release)/")!
            let checksumURL = directoryURL.appendingPathComponent("\(fileName).sha256")
            guard let line = LinuxDiscoveryParsing.checksumLines(
                from: try await fetchText(checksumURL)
            ).first(where: { $0.fileName == fileName }) else {
                throw LinuxDiscoveryError.unreadableContent(checksumURL)
            }
            entries.append(
                LinuxImageEntry(
                    distribution: .cachyos,
                    edition: edition,
                    version: release,
                    isLongTermSupport: false,
                    architecture: .x86_64,
                    fileName: fileName,
                    downloadURL: directoryURL.appendingPathComponent(fileName),
                    checksumSourceURL: checksumURL,
                    expectedSHA256: line.sha256
                )
            )
        }
        return entries
    }

    // MARK: - Networking

    func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw LinuxDiscoveryError.invalidResponse(url, statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw LinuxDiscoveryError.unreadableContent(url)
        }
        return text
    }

    func probeSize(of url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        guard
            let (_, response) = try? await session.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            httpResponse.expectedContentLength > 0
        else { return nil }
        return httpResponse.expectedContentLength
    }
}
