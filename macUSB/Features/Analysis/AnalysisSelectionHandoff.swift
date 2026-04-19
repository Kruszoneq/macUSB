import Foundation

@MainActor
final class AnalysisSelectionHandoff {
    static let shared = AnalysisSelectionHandoff()

    private var pendingInstallerURL: URL?

    private init() {}

    func setPendingInstallerURL(_ url: URL) {
        pendingInstallerURL = url.standardizedFileURL
    }

    func consumePendingInstallerURL() -> URL? {
        defer { pendingInstallerURL = nil }
        return pendingInstallerURL
    }
}
