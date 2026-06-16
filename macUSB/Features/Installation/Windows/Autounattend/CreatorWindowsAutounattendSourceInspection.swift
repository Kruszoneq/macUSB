import Foundation

enum CreatorWindowsAutounattendSourceInspection {
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
