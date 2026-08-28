import Foundation

enum MacOSDiskImageNamingPolicy {
    static func baseName(for entry: MacOSInstallerEntry) -> String {
        let family = sanitizedComponent(entry.family)
        let version = sanitizedComponent(entry.version)
        let betaSuffix = entry.releaseChannel == .publicBeta ? " Beta" : ""
        return "\(family) \(version)\(betaSuffix)"
    }

    static func preferredFileName(for entry: MacOSInstallerEntry) -> String {
        "\(baseName(for: entry)).dmg"
    }

    static func firstAvailableURL(
        in directoryURL: URL,
        preferredFileName: String,
        fileManager: FileManager = .default
    ) -> URL {
        let preferredURL = directoryURL.appendingPathComponent(preferredFileName)
        guard fileManager.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let fileExtension = preferredURL.pathExtension
        let stem = preferredURL.deletingPathExtension().lastPathComponent
        var suffix = 2

        while true {
            let candidateName = fileExtension.isEmpty
                ? "\(stem) (\(suffix))"
                : "\(stem) (\(suffix)).\(fileExtension)"
            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }

    private static func sanitizedComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.controlCharacters)
        let components = value.components(separatedBy: invalidCharacters)
        let sanitized = components
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "macOS" : sanitized
    }
}
