import Foundation
import Combine

@MainActor
final class LinuxDownloaderLogic: ObservableObject {
    @Published private(set) var state: DownloaderDiscoveryState = .idle
    @Published private(set) var distributionGroups: [LinuxDistributionGroup] = []
    @Published private(set) var unavailableSources: [LinuxDiscoverySource] = []
    @Published private(set) var errorText: String?

    private var discoveryTask: Task<Void, Never>?
    private var downloadedCheckDirectoryURL: URL?

    var hasStartedDiscovery: Bool {
        state != .idle || discoveryTask != nil
    }

    func startDiscovery(destinationDirectoryURL: URL) {
        cancelDiscovery(updateState: false)
        state = .loading
        errorText = nil
        downloadedCheckDirectoryURL = destinationDirectoryURL

        AppLogging.info(
            "Linux image discovery started (sources: \(LinuxDiscoverySource.allCases.map(\.rawValue).joined(separator: ", "))).",
            stage: .downloader, workflow: .discovery
        )

        discoveryTask = Task { [weak self] in
            let sources = LinuxDiscoverySources(session: LinuxDiscoverySources.makeSession())
            let results = await Self.discoverAllSources(using: sources)
            guard !Task.isCancelled else { return }

            var entries: [LinuxImageEntry] = []
            var failedSources: [LinuxDiscoverySource] = []
            var lastErrorText: String?
            for source in LinuxDiscoverySource.allCases {
                switch results[source] {
                case let .success(sourceEntries):
                    AppLogging.info(
                        "Linux discovery source \(source.rawValue) returned \(sourceEntries.count) images.",
                        stage: .downloader, workflow: .discovery
                    )
                    entries += sourceEntries
                case let .failure(error):
                    AppLogging.error(
                        "Linux discovery source \(source.rawValue) is unavailable: \(error.localizedDescription)",
                        stage: .downloader, workflow: .discovery
                    )
                    failedSources.append(source)
                    lastErrorText = error.localizedDescription
                case nil:
                    failedSources.append(source)
                }
            }

            let sizedEntries = await Self.probeSizes(of: entries, using: sources)
            guard !Task.isCancelled, let self else { return }

            self.unavailableSources = failedSources
            self.distributionGroups = Self.group(sizedEntries)
            self.refreshDownloadedState(destinationDirectoryURL: destinationDirectoryURL)
            if sizedEntries.isEmpty {
                self.errorText = lastErrorText
                self.state = .failed
            } else {
                self.state = .loaded
            }
            self.discoveryTask = nil

            AppLogging.info(
                "Linux image discovery finished. Images=\(sizedEntries.count), unavailable sources=\(failedSources.map(\.rawValue)).",
                stage: .downloader, workflow: .discovery
            )
        }
    }

    func cancelDiscovery(updateState: Bool = true) {
        guard let discoveryTask else { return }
        discoveryTask.cancel()
        self.discoveryTask = nil
        if updateState {
            state = .cancelled
            AppLogging.info("Linux image discovery cancelled.", stage: .downloader, workflow: .discovery)
        }
    }

    /// Marks entries whose file name already exists in the destination folder.
    func refreshDownloadedState(destinationDirectoryURL: URL) {
        downloadedCheckDirectoryURL = destinationDirectoryURL
        distributionGroups = distributionGroups.map { group in
            LinuxDistributionGroup(
                distribution: group.distribution,
                entries: group.entries.map { entry in
                    var updated = entry
                    updated.isDownloaded = FileManager.default.fileExists(
                        atPath: destinationDirectoryURL.appendingPathComponent(entry.fileName).path
                    )
                    return updated
                }
            )
        }
    }

    private static func discoverAllSources(
        using sources: LinuxDiscoverySources
    ) async -> [LinuxDiscoverySource: Result<[LinuxImageEntry], Error>] {
        await withTaskGroup(of: (LinuxDiscoverySource, Result<[LinuxImageEntry], Error>).self) { group in
            for source in LinuxDiscoverySource.allCases {
                group.addTask {
                    do {
                        return (source, .success(try await sources.entries(for: source)))
                    } catch {
                        return (source, .failure(error))
                    }
                }
            }

            var results: [LinuxDiscoverySource: Result<[LinuxImageEntry], Error>] = [:]
            for await (source, result) in group {
                results[source] = result
            }
            return results
        }
    }

    private static func probeSizes(
        of entries: [LinuxImageEntry],
        using sources: LinuxDiscoverySources
    ) async -> [LinuxImageEntry] {
        await withTaskGroup(of: (Int, Int64?).self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    (index, await sources.probeSize(of: entry.downloadURL))
                }
            }

            var sized = entries
            for await (index, size) in group {
                sized[index].sizeBytes = size
            }
            return sized
        }
    }

    private static func group(_ entries: [LinuxImageEntry]) -> [LinuxDistributionGroup] {
        LinuxDistribution.allCases.compactMap { distribution in
            let distributionEntries = entries
                .filter { $0.distribution == distribution }
                .sorted { lhs, rhs in
                    let versionOrder = LinuxDiscoveryParsing.compareVersions(lhs.version, rhs.version)
                    if versionOrder != .orderedSame {
                        return versionOrder == .orderedDescending
                    }
                    if lhs.edition != rhs.edition {
                        return lhs.edition < rhs.edition
                    }
                    return lhs.architecture == .x86_64 && rhs.architecture == .arm64
                }
            guard !distributionEntries.isEmpty else { return nil }
            return LinuxDistributionGroup(distribution: distribution, entries: distributionEntries)
        }
    }
}
