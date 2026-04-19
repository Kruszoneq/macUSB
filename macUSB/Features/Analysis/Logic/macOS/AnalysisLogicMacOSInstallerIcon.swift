import AppKit
import Foundation

extension AnalysisLogic {
    func updateDetectedSystemIcon(from appURL: URL?) {
        guard let appURL = appURL else {
            self.detectedSystemIcon = nil
            return
        }

        let iconFileCandidates = [
            "ProductPageIcon.icns",
            "InstallAssistant.icns",
            "Install Mac OS X.icns"
        ]

        for installerURL in self.candidateInstallerLocations(from: appURL) {
            let resourcesURL = installerURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            self.log("Próba odczytu ikony systemu z katalogu: \(resourcesURL.path)")
            guard let iconURL = self.findIconURL(in: resourcesURL, preferredFileNames: iconFileCandidates),
                  let icon = NSImage(contentsOf: iconURL) else {
                continue
            }

            self.detectedSystemIcon = icon
            self.log("Odczytano ikonę systemu z pliku: \(iconURL.path)")
            return
        }

        self.detectedSystemIcon = nil
        self.log("Nie znaleziono ikony instalatora (\(iconFileCandidates.joined(separator: ", "))) dla: \(appURL.path)")
    }

    private func candidateInstallerLocations(from url: URL) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default

        func appendUnique(_ candidate: URL) {
            let normalized = candidate.standardizedFileURL
            guard !result.contains(where: { $0.standardizedFileURL == normalized }) else { return }
            result.append(candidate)
        }

        appendUnique(url)

        if url.pathExtension.lowercased() != "app" {
            // Część starych obrazów ma instalator pod klasyczną nazwą "Install Mac OS X".
            appendUnique(url.appendingPathComponent("Install Mac OS X.app", isDirectory: true))
            appendUnique(url.appendingPathComponent("Install OS X.app", isDirectory: true))
            appendUnique(url.appendingPathComponent("Install macOS.app", isDirectory: true))

            if let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for child in children where child.pathExtension.lowercased() == "app" {
                    appendUnique(child)
                }
            }
        }

        return result.filter { fm.fileExists(atPath: $0.path) }
    }

    private func findIconURL(in resourcesURL: URL, preferredFileNames: [String]) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: resourcesURL.path),
              let files = try? fm.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }

        var byLowercasedName: [String: URL] = [:]
        for file in files {
            byLowercasedName[file.lastPathComponent.lowercased()] = file
        }

        for fileName in preferredFileNames {
            if let match = byLowercasedName[fileName.lowercased()] {
                return match
            }
        }

        return nil
    }
}
