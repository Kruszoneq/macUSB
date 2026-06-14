import Foundation

enum CreatorWindowsAutounattendSourceInspection {
    static func existingAutounattendPath(in mountedSourcePath: String?) -> String? {
        guard let mountedSourcePath = mountedSourcePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mountedSourcePath.isEmpty else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: mountedSourcePath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents.first {
            $0.lastPathComponent.caseInsensitiveCompare("Autounattend.xml") == .orderedSame
        }?.path
    }
}
