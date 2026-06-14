import Foundation

@MainActor
final class AnalysisSelectionHandoff {
    static let shared = AnalysisSelectionHandoff()

    private var pendingInstallerURL: URL?
    private var pendingRawLinuxImageURL: URL?

    private init() {}

    func setPendingInstallerURL(_ url: URL) {
        pendingInstallerURL = url.standardizedFileURL
    }

    func consumePendingInstallerURL() -> URL? {
        defer { pendingInstallerURL = nil }
        return pendingInstallerURL
    }

    func setPendingRawLinuxImageURL(_ url: URL) {
        pendingRawLinuxImageURL = url.standardizedFileURL
    }

    func consumePendingRawLinuxImageURL() -> URL? {
        defer { pendingRawLinuxImageURL = nil }
        return pendingRawLinuxImageURL
    }
}
