import Foundation
import SwiftUI
import Combine

struct MacOSInstallerEntry: Identifiable, Hashable {
    let id: String
    let family: String
    let name: String
    let version: String
    let build: String
    let sourceURL: URL

    var displayTitle: String {
        "\(name) \(version) (\(build))"
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

@MainActor
final class MacOSDownloaderLogic: ObservableObject {
    @Published private(set) var state: DownloaderDiscoveryState = .idle
    @Published private(set) var familyGroups: [MacOSInstallerFamilyGroup] = []
    @Published private(set) var statusText: String = ""
    @Published private(set) var errorText: String?

    var isLoading: Bool {
        state == .loading
    }

    private var discoveryTask: Task<Void, Never>?
    private let catalogService: MacOSCatalogService

    init(session: URLSession = .shared) {
        self.catalogService = MacOSCatalogService(session: session)
    }

    func startDiscovery() {
        cancelDiscovery(updateState: false)
        state = .loading
        errorText = nil
        statusText = String(localized: "Laczenie z serwerami Apple...")

        AppLogging.stage("Downloader: Rozpoczecie sprawdzania dostepnych wersji")
        AppLogging.info("Start sprawdzania dostepnych instalatorow macOS/OS X.", category: "Downloader")

        discoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.runDiscovery()
        }
    }

    func cancelDiscovery(updateState: Bool = true) {
        guard let discoveryTask else { return }
        discoveryTask.cancel()
        self.discoveryTask = nil

        if updateState {
            state = .cancelled
            statusText = ""
            AppLogging.info("Anulowano sprawdzanie dostepnych wersji systemow.", category: "Downloader")
        }
    }

    private func runDiscovery() async {
        do {
            let entries = try await catalogService.fetchStableInstallers { [weak self] phase in
                Task { @MainActor [weak self] in
                    self?.statusText = phase
                }
            }

            try Task.checkCancellation()

            familyGroups = Self.makeGroups(from: entries)
            state = .loaded
            statusText = ""
            discoveryTask = nil

            AppLogging.info(
                "Sprawdzanie zakonczone sukcesem. Znaleziono \(entries.count) pozycji.",
                category: "Downloader"
            )
        } catch is CancellationError {
            state = .cancelled
            statusText = ""
            discoveryTask = nil
            AppLogging.info("Sprawdzanie przerwane przez uzytkownika.", category: "Downloader")
        } catch {
            state = .failed
            statusText = ""
            errorText = error.localizedDescription
            discoveryTask = nil
            AppLogging.error(
                "Blad podczas sprawdzania wersji systemow: \(error.localizedDescription)",
                category: "Downloader"
            )
        }
    }

    private static func makeGroups(from entries: [MacOSInstallerEntry]) -> [MacOSInstallerFamilyGroup] {
        let grouped = Dictionary(grouping: entries) { $0.family }
        let groups = grouped.map { family, familyEntries in
            MacOSInstallerFamilyGroup(
                family: family,
                entries: familyEntries.sorted { lhs, rhs in
                    if lhs.version.compare(rhs.version, options: .numeric) != .orderedSame {
                        return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
                    }
                    if lhs.build.compare(rhs.build, options: .numeric) != .orderedSame {
                        return lhs.build.compare(rhs.build, options: .numeric) == .orderedDescending
                    }
                    return lhs.name < rhs.name
                }
            )
        }

        return groups.sorted { lhs, rhs in
            let lhsTopVersion = lhs.entries.first?.version ?? "0"
            let rhsTopVersion = rhs.entries.first?.version ?? "0"
            if lhsTopVersion.compare(rhsTopVersion, options: .numeric) != .orderedSame {
                return lhsTopVersion.compare(rhsTopVersion, options: .numeric) == .orderedDescending
            }
            return lhs.family < rhs.family
        }
    }
}

private struct MacOSCatalogService {
    typealias PhaseSink = @Sendable (String) -> Void

    private struct CatalogCandidate {
        let distributionURL: URL
        let sourceURL: URL
    }

    private struct LegacySupportEntry {
        let label: String
        let name: String
        let version: String
    }

    private enum Constants {
        static let catalogURL = URL(string: "https://swscan.apple.com/content/catalogs/others/index-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz")!
        static let supportArticleURL = URL(string: "https://support.apple.com/en-us/102662")!
        static let requestTimeout: TimeInterval = 30
        static let allowedHosts: Set<String> = [
            "swscan.apple.com",
            "swdist.apple.com",
            "swcdn.apple.com",
            "support.apple.com",
            "updates-http.cdn-apple.com",
            "updates.cdn-apple.com",
            "apps.apple.com"
        ]

        static let legacySupportMap: [LegacySupportEntry] = [
            LegacySupportEntry(label: "Sierra 10.12", name: "macOS Sierra", version: "10.12"),
            LegacySupportEntry(label: "El Capitan 10.11", name: "OS X El Capitan", version: "10.11"),
            LegacySupportEntry(label: "Yosemite 10.10", name: "OS X Yosemite", version: "10.10"),
            LegacySupportEntry(label: "Mountain Lion 10.8", name: "OS X Mountain Lion", version: "10.8"),
            LegacySupportEntry(label: "Lion 10.7", name: "Mac OS X Lion", version: "10.7")
        ]
    }

    private enum DiscoveryError: LocalizedError {
        case blockedHost(URL)
        case invalidResponse(URL)
        case invalidCatalogFormat

        var errorDescription: String? {
            switch self {
            case let .blockedHost(url):
                return "URL poza allowlista Apple: \(url.absoluteString)"
            case let .invalidResponse(url):
                return "Niepoprawna odpowiedz serwera dla: \(url.absoluteString)"
            case .invalidCatalogFormat:
                return "Nie udalo sie sparsowac katalogu Apple."
            }
        }
    }

    let session: URLSession

    func fetchStableInstallers(phase: @escaping PhaseSink) async throws -> [MacOSInstallerEntry] {
        try Task.checkCancellation()

        phase(String(localized: "Pobieranie katalogu Apple..."))
        AppLogging.info("Pobieranie katalogu installerow z Apple.", category: "Downloader")
        let catalogData = try await fetchData(from: Constants.catalogURL)
        let candidates = try parseCatalogCandidates(from: catalogData)
        AppLogging.info("W katalogu znaleziono \(candidates.count) kandydatow InstallAssistant.", category: "Downloader")

        phase(String(localized: "Analiza metadanych wersji..."))
        AppLogging.info("Rozpoczecie parsowania plikow .dist.", category: "Downloader")
        var entries: [MacOSInstallerEntry] = []
        entries.reserveCapacity(candidates.count + Constants.legacySupportMap.count)

        for candidate in candidates {
            try Task.checkCancellation()
            if let parsed = try await parseDistributionCandidate(candidate) {
                entries.append(parsed)
            }
        }

        phase(String(localized: "Dolaczanie starszych wersji z Apple Support..."))
        AppLogging.info("Dolaczanie starszych wpisow z Apple Support.", category: "Downloader")
        let legacyEntries = try await fetchLegacySupportEntries()
        entries.append(contentsOf: legacyEntries)

        let uniqueEntries = deduplicated(entries)
        AppLogging.info("Po deduplikacji pozostalo \(uniqueEntries.count) wpisow stable.", category: "Downloader")
        return uniqueEntries
    }

    private func parseCatalogCandidates(from data: Data) throws -> [CatalogCandidate] {
        guard
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let products = plist["Products"] as? [String: Any]
        else {
            throw DiscoveryError.invalidCatalogFormat
        }

        var candidates: [CatalogCandidate] = []
        candidates.reserveCapacity(products.count)

        for value in products.values {
            guard let product = value as? [String: Any] else { continue }
            guard
                let extendedMeta = product["ExtendedMetaInfo"] as? [String: Any],
                extendedMeta["InstallAssistantPackageIdentifiers"] != nil
            else {
                continue
            }

            guard
                let distributions = product["Distributions"] as? [String: Any],
                let distributionURL = preferredDistributionURL(from: distributions)
            else {
                continue
            }

            let sourceURL = preferredInstallAssistantPackageURL(from: product) ?? distributionURL
            candidates.append(
                CatalogCandidate(distributionURL: distributionURL, sourceURL: sourceURL)
            )
        }

        return candidates
    }

    private func preferredDistributionURL(from distributions: [String: Any]) -> URL? {
        let preferredKeys = ["English", "en", "en_US", "en_GB", "en_AU"]

        for key in preferredKeys {
            if let urlString = distributions[key] as? String, let url = URL(string: urlString) {
                return url
            }
        }

        for value in distributions.values {
            if let urlString = value as? String, let url = URL(string: urlString) {
                return url
            }
        }

        return nil
    }

    private func preferredInstallAssistantPackageURL(from product: [String: Any]) -> URL? {
        guard let packages = product["Packages"] as? [[String: Any]] else { return nil }

        for package in packages {
            guard let urlString = package["URL"] as? String else { continue }
            guard urlString.localizedCaseInsensitiveContains("InstallAssistant") else { continue }
            guard let url = URL(string: urlString) else { continue }
            return url
        }

        return nil
    }

    private func parseDistributionCandidate(_ candidate: CatalogCandidate) async throws -> MacOSInstallerEntry? {
        let data = try await fetchData(from: candidate.distributionURL)
        guard let distText = String(data: data, encoding: .utf8) else { return nil }

        guard var name = extractFirstMatch(in: distText, pattern: #"suDisabledGroupID="([^"]+)""#) else {
            return nil
        }

        name = name.replacingOccurrences(of: "Install ", with: "")
        let version = extractFirstMatch(in: distText, pattern: #"<key>VERSION</key>\s*<string>([^<]+)</string>"#) ?? ""
        var build = extractFirstMatch(in: distText, pattern: #"<key>BUILD</key>\s*<string>([^<]+)</string>"#) ?? "N/A"

        if version.isEmpty { return nil }
        if build.isEmpty { build = "N/A" }
        if isPrerelease(name: name, version: version, build: build) { return nil }

        let family = normalizeFamilyName(from: name)
        return MacOSInstallerEntry(
            id: "\(family)|\(name)|\(version)|\(build)",
            family: family,
            name: name,
            version: version,
            build: build,
            sourceURL: candidate.sourceURL
        )
    }

    private func fetchLegacySupportEntries() async throws -> [MacOSInstallerEntry] {
        let supportData = try await fetchData(from: Constants.supportArticleURL)
        guard let html = String(data: supportData, encoding: .utf8) else { return [] }

        var entries: [MacOSInstallerEntry] = []
        entries.reserveCapacity(Constants.legacySupportMap.count)

        for legacy in Constants.legacySupportMap {
            try Task.checkCancellation()

            let escapedLabel = NSRegularExpression.escapedPattern(for: legacy.label)
            let pattern = #"<a href="([^"]+)"[^>]*>"# + escapedLabel + #"</a>"#
            guard
                let href = extractFirstMatch(in: html, pattern: pattern),
                let sourceURL = URL(string: href)
            else {
                continue
            }

            guard isAllowedHost(sourceURL) else { continue }

            entries.append(
                MacOSInstallerEntry(
                    id: "\(legacy.name)|\(legacy.version)|N/A",
                    family: legacy.name,
                    name: legacy.name,
                    version: legacy.version,
                    build: "N/A",
                    sourceURL: sourceURL
                )
            )
        }

        return entries
    }

    private func deduplicated(_ entries: [MacOSInstallerEntry]) -> [MacOSInstallerEntry] {
        var seen: Set<String> = []
        var result: [MacOSInstallerEntry] = []
        result.reserveCapacity(entries.count)

        for entry in entries {
            let key = "\(entry.name)|\(entry.version)|\(entry.build)"
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }

        return result
    }

    private func fetchData(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard isAllowedHost(url) else {
            throw DiscoveryError.blockedHost(url)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = Constants.requestTimeout

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw DiscoveryError.invalidResponse(url)
        }

        return data
    }

    private func isAllowedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return Constants.allowedHosts.contains(host)
    }

    private func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }

        guard let resultRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[resultRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeFamilyName(from name: String) -> String {
        if name.hasPrefix("Install ") {
            return String(name.dropFirst("Install ".count))
        }
        return name
    }

    private func isPrerelease(name: String, version: String, build: String) -> Bool {
        let text = "\(name) \(version) \(build)".lowercased()
        return text.contains("beta")
            || text.contains("seed")
            || text.contains("release candidate")
            || text.contains(" rc")
            || text.contains("preview")
    }
}
