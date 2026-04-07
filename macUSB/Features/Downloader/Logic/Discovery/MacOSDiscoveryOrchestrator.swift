import SwiftUI
import Combine

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
        statusText = String(localized: "Łączenie z serwerami Apple...")

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
}
