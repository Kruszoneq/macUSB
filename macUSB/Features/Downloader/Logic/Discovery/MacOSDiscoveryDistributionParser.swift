import Foundation

extension MacOSCatalogService {
    func parseDistributionCandidate(_ candidate: CatalogCandidate) async throws -> MacOSInstallerEntry? {
        let data = try await fetchData(from: candidate.distributionURL)
        guard let distText = String(data: data, encoding: .utf8) else { return nil }

        guard var name = extractFirstMatch(in: distText, pattern: #"suDisabledGroupID=\"([^\"]+)\""#) else {
            return nil
        }

        name = name.replacingOccurrences(of: "Install ", with: "")
        let version = extractFirstMatch(in: distText, pattern: #"<key>VERSION</key>\s*<string>([^<]+)</string>"#) ?? ""
        var build = extractFirstMatch(in: distText, pattern: #"<key>BUILD</key>\s*<string>([^<]+)</string>"#) ?? "N/A"

        if version.isEmpty { return nil }
        if build.isEmpty { build = "N/A" }
        let family = normalizeFamilyName(from: name)
        return MacOSInstallerEntry(
            id: "\(candidate.releaseChannel.rawValue)|\(family)|\(name)|\(version)|\(build)",
            family: family,
            name: name,
            version: version,
            build: build,
            installerSizeText: candidate.catalogSizeBytes.map(formatSizeInGigabytes),
            sourceURL: candidate.sourceURL,
            catalogProductID: candidate.productID,
            releaseChannel: candidate.releaseChannel,
            catalogURL: candidate.catalogURL
        )
    }

    func extractFirstMatch(in text: String, pattern: String) -> String? {
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

    func normalizeFamilyName(from name: String) -> String {
        var family = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if family.hasPrefix("Install ") {
            family = String(family.dropFirst("Install ".count))
        }

        let prereleaseSuffixPatterns = [
            #"\s+(?:(?:Public|Developer)\s+)?(?:Beta|Seed|Preview)(?:\s+\d+)?$"#,
            #"\s+(?:Release Candidate|RC)(?:\s+\d+)?$"#,
        ]
        for pattern in prereleaseSuffixPatterns {
            family = family.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        family = family.trimmingCharacters(in: .whitespacesAndNewlines)

        if family.localizedCaseInsensitiveContains("golden gate") {
            return "macOS Golden Gate"
        }
        return family
    }
}
