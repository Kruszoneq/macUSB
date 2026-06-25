import Foundation

enum CreatorWindowsAutounattendSourceInspection {
    static func availableLanguageTags(in mountedSourcePath: String?) -> Set<String>? {
        guard let mountedSourcePath = mountedSourcePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mountedSourcePath.isEmpty else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: mountedSourcePath)
        guard let sourcesURL = childURL(named: "sources", in: rootURL),
              let langIniURL = childURL(named: "lang.ini", in: sourcesURL),
              let content = langIniContent(at: langIniURL) else {
            return nil
        }

        var isInAvailableLanguagesSection = false
        var tags = Set<String>()

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else {
                continue
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                let sectionName = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                isInAvailableLanguagesSection = sectionName.caseInsensitiveCompare("Available UI Languages") == .orderedSame
                continue
            }

            guard isInAvailableLanguagesSection else { continue }

            let key = line
                .split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
                .first?
                .description
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalized = CreatorWindowsAutounattendMacLocale.normalizedWindowsTag(key) {
                tags.insert(normalized.lowercased())
            }
        }

        return tags.isEmpty ? nil : tags
    }

    private static func langIniContent(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16LittleEndian)
            ?? String(data: data, encoding: .utf16)
    }

    static func existingAutounattendPath(in mountedSourcePath: String?) -> String? {
        guard let mountedSourcePath = mountedSourcePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mountedSourcePath.isEmpty else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: mountedSourcePath)
        if let rootAutounattendPath = childURL(
            named: "Autounattend.xml",
            in: rootURL
        )?.path {
            return rootAutounattendPath
        }

        return nestedChildURL(
            from: rootURL,
            components: ["sources", "$OEM$", "$$", "Panther", "unattend.xml"]
        )?.path
    }

    private static func nestedChildURL(from rootURL: URL, components: [String]) -> URL? {
        var currentURL = rootURL
        for component in components {
            guard let nextURL = childURL(named: component, in: currentURL) else {
                return nil
            }
            currentURL = nextURL
        }
        return currentURL
    }

    private static func childURL(named name: String, in directoryURL: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents.first {
            $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
