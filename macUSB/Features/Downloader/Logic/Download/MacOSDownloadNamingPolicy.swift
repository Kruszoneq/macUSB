import Foundation

extension MontereyDownloadFlowModel {
    func sanitizeFileName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "_",
            options: .regularExpression
        )
    }

    func destinationFileName(
        for item: DownloadManifestItem,
        index: Int,
        manifest: DownloadManifest
    ) -> String {
        if usesLegacyInstallerWorkflow(for: manifest) {
            let preserved = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preserved.isEmpty {
                return preserved.replacingOccurrences(of: "/", with: "_")
            }
        }
        return "\(index + 1)_\(sanitizeFileName(item.name))"
    }

    func usesLegacyInstallerWorkflow(for manifest: DownloadManifest) -> Bool {
        manifest.items.contains { item in
            item.name.caseInsensitiveCompare("InstallAssistantAuto.pkg") == .orderedSame
                || item.url.lastPathComponent.caseInsensitiveCompare("InstallAssistantAuto.pkg") == .orderedSame
        }
    }
}
