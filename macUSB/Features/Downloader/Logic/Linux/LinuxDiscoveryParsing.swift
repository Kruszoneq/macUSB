import Foundation

enum LinuxDiscoveryParsing {
    struct ChecksumLine: Hashable {
        let sha256: String
        let fileName: String
    }

    /// Parses `SHA256SUMS`-style lists in both text (`hash  name`) and binary (`hash *name`) notation.
    static func checksumLines(from text: String) -> [ChecksumLine] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let parts = rawLine.split(
                maxSplits: 1,
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard parts.count == 2 else { return nil }

            let hash = parts[0].lowercased()
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }

            var fileName = parts[1].trimmingCharacters(in: .whitespaces)
            if fileName.hasPrefix("*") {
                fileName.removeFirst()
            }
            guard !fileName.isEmpty, !fileName.contains("/") else { return nil }
            return ChecksumLine(sha256: hash, fileName: fileName)
        }
    }

    /// Returns directory names from an HTML index page whose names fully match `pattern`.
    static func directoryNames(fromIndexHTML html: String, matching pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"href="([^"/?#]+)/?""#) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        let names = regex.matches(in: html, range: range).compactMap { match -> String? in
            guard let nameRange = Range(match.range(at: 1), in: html) else { return nil }
            let name = String(html[nameRange])
            return name.range(of: "^\(pattern)$", options: .regularExpression) != nil ? name : nil
        }
        return Array(Set(names))
    }

    /// Captures regex groups of `pattern` matched against the full `text`.
    static func captures(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: "^\(pattern)$") else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let captureRange = Range(match.range(at: index), in: text) else { return "" }
            return String(text[captureRange])
        }
    }

    /// Orders versions such as `26.04.1`, `9.2-1` or `260809` by their numeric components.
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = numericComponents(lhs)
        let right = numericComponents(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l < r ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    static func newestVersion(in versions: [String]) -> String? {
        versions.max { compareVersions($0, $1) == .orderedAscending }
    }

    /// Keeps the newest entry per image line.
    static func newestPerLine(_ entries: [LinuxImageEntry]) -> [LinuxImageEntry] {
        var newest: [String: LinuxImageEntry] = [:]
        for entry in entries {
            if let existing = newest[entry.lineKey],
               compareVersions(existing.version, entry.version) != .orderedAscending {
                continue
            }
            newest[entry.lineKey] = entry
        }
        return Array(newest.values)
    }

    private static func numericComponents(_ version: String) -> [Int] {
        version
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }
}
