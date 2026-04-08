import Foundation

struct MacOSCatalogService {
    typealias PhaseSink = @Sendable (String) -> Void

    let session: URLSession
}

extension MacOSCatalogService {
    struct CatalogCandidate {
        let productID: String
        let distributionURL: URL
        let sourceURL: URL
        let catalogSizeBytes: Int64?
    }

    struct LegacySupportEntry {
        let label: String
        let name: String
        let version: String
    }

    enum Constants {
        static let catalogURL = URL(string: "https://swscan.apple.com/content/catalogs/others/index-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz")!
        static let supportArticleURL = URL(string: "https://support.apple.com/en-us/102662")!
        static let requestTimeout: TimeInterval = 30
        static let byteRangeProbe = "bytes=0-0"
        static let maxSizeProbeConcurrency = 5
        static let maxSizeProbeAttempts = 3
        static let sizeProbeRetryBaseDelayNanoseconds: UInt64 = 400_000_000
        static let downloadableExtensions: Set<String> = ["pkg", "dmg", "ipsw"]
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
            LegacySupportEntry(
                label: "Sierra 10.12",
                name: "macOS Sierra",
                version: "10.12.6"
            ),
            LegacySupportEntry(
                label: "El Capitan 10.11",
                name: "OS X El Capitan",
                version: "10.11.6"
            ),
            LegacySupportEntry(
                label: "Yosemite 10.10",
                name: "OS X Yosemite",
                version: "10.10.5"
            ),
            LegacySupportEntry(
                label: "Mountain Lion 10.8",
                name: "OS X Mountain Lion",
                version: "10.8.5"
            ),
            LegacySupportEntry(
                label: "Lion 10.7",
                name: "Mac OS X Lion",
                version: "10.7.5"
            )
        ]

        static let legacyAssemblyRequiredPackageIdentifiers: [String] = [
            "com.apple.pkg.InstallAssistantAuto",
            "com.apple.pkg.RecoveryHDMetaDmg",
            "com.apple.pkg.InstallESDDmg"
        ]

        static let legacyAssemblyRequiredFileNames: [String] = [
            "InstallAssistantAuto.pkg",
            "RecoveryHDMetaDmg.pkg",
            "InstallESDDmg.pkg"
        ]
    }

    enum ProbeMethod: String {
        case head = "HEAD"
        case range = "RANGE"
    }

    struct SizeProbeSummary {
        let totalEntries: Int
        let catalogPrefilledSizes: Int
        let resolvedByNetworkProbe: Int
        let unresolvedAfterProbe: Int
        let skippedDueToTrustFailedHost: Int
        let retriesPerformed: Int
        let trustFailedHosts: Int
        let suppressedRepeatedFailureLogs: Int
    }

    struct SizeProbeResult {
        let index: Int
        let sizeText: String?
        let retriesPerformed: Int
        let skippedDueToTrustFailedHost: Int
    }

    struct SizeProbeFetchOutcome {
        let sizeText: String?
        let retriesPerformed: Int
        let skippedDueToTrustFailedHost: Int
    }

    struct CatalogPackageDescriptor {
        let name: String
        let url: URL
        let packageIdentifier: String?
        let sizeBytes: Int64?
        let digest: String?
        let digestAlgorithm: String?
        let integrityDataURL: URL?
    }

    actor SizeProbeRunState {
        private var trustFailedHosts: Set<String> = []
        private var loggedFailureKeys: Set<String> = []
        private var suppressedRepeatedFailureLogs: Int = 0

        func isTrustFailedHost(_ host: String) -> Bool {
            trustFailedHosts.contains(host)
        }

        func markTrustFailedHost(_ host: String) {
            trustFailedHosts.insert(host)
        }

        func shouldLogFailure(for key: String) -> Bool {
            if loggedFailureKeys.insert(key).inserted {
                return true
            }
            suppressedRepeatedFailureLogs += 1
            return false
        }

        func summarySnapshot() -> (trustFailedHosts: Int, suppressedRepeatedFailureLogs: Int) {
            (trustFailedHosts.count, suppressedRepeatedFailureLogs)
        }
    }

    enum DiscoveryError: LocalizedError {
        case blockedHost(URL)
        case invalidResponse(URL)
        case invalidCatalogFormat
        case productNotFound(String)
        case unsupportedEntry
        case emptyDownloadManifest

        var errorDescription: String? {
            switch self {
            case let .blockedHost(url):
                return "URL poza allowlista Apple: \(url.absoluteString)"
            case let .invalidResponse(url):
                return "Niepoprawna odpowiedz serwera dla: \(url.absoluteString)"
            case .invalidCatalogFormat:
                return "Nie udalo sie sparsowac katalogu Apple."
            case let .productNotFound(productID):
                return "Nie znaleziono produktu \(productID) w katalogu Apple."
            case .unsupportedEntry:
                return "Wybrana pozycja nie jest wspierana w aktualnym przeplywie pobierania."
            case .emptyDownloadManifest:
                return "Katalog Apple nie zwrocil plikow do pobrania."
            }
        }
    }
}
