import Foundation

extension MacOSCatalogService {
    func fetchLegacySupportEntries() async throws -> [MacOSInstallerEntry] {
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
                    installerSizeText: nil,
                    sourceURL: sourceURL,
                    catalogProductID: nil
                )
            )
        }

        return entries
    }
}
