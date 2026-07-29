import SwiftUI
import Combine

@MainActor
final class MacOSDownloaderLogic: ObservableObject {
    @Published private(set) var state: DownloaderDiscoveryState = .idle
    @Published private(set) var familyGroups: [MacOSInstallerFamilyGroup] = []
    @Published private(set) var statusText: String = ""
    @Published private(set) var errorText: String?
    @Published private(set) var unrecognizedLocalInstallerCount = 0

    var isLoading: Bool {
        state == .loading
    }

    private var discoveryTask: Task<Void, Never>?
    private let catalogService: MacOSCatalogService

    init(session: URLSession = .shared) {
        self.catalogService = MacOSCatalogService(session: session)
    }

    func startDiscovery(includePublicBetaVersions: Bool = false) {
        cancelDiscovery(updateState: false)
        state = .loading
        errorText = nil
        unrecognizedLocalInstallerCount = 0
        statusText = String(localized: "Łączenie z serwerami Apple...")

        AppLogging.stage("Downloader: Rozpoczecie sprawdzania dostepnych wersji")
        AppLogging.info("Start sprawdzania dostepnych instalatorow macOS/OS X.", category: "Downloader")

        discoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.runDiscovery(includePublicBetaVersions: includePublicBetaVersions)
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

    func prepareDownloadManifest(
        for entry: MacOSInstallerEntry,
        phase: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadManifest {
        try await catalogService.fetchDownloadManifest(for: entry, phase: phase)
    }

    func isOldestDownloadTarget(_ entry: MacOSInstallerEntry) -> Bool {
        catalogService.isOldestInstallerTarget(entry)
    }

    func isLegacyAssemblyTarget(_ entry: MacOSInstallerEntry) -> Bool {
        catalogService.isLegacyAssemblyTarget(entry)
    }

    func supportsProductionDownload(_ entry: MacOSInstallerEntry) -> Bool {
        catalogService.isSupportedDownloadTarget(entry)
    }

    private func runDiscovery(includePublicBetaVersions: Bool) async {
        do {
            let result = try await catalogService.fetchInstallers(
                includePublicBetaVersions: includePublicBetaVersions
            ) { [weak self] phase in
                Task { @MainActor [weak self] in
                    self?.statusText = phase
                }
            }

            try Task.checkCancellation()

            familyGroups = Self.makeGroups(from: result.entries)
            unrecognizedLocalInstallerCount = result.unrecognizedLocalInstallerCount
            state = .loaded
            statusText = ""
            discoveryTask = nil

            AppLogging.info(
                "Sprawdzanie zakonczone sukcesem. Znaleziono \(result.entries.count) pozycji, nierozpoznane lokalne instalatory: \(result.unrecognizedLocalInstallerCount).",
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
}
