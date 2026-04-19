import Foundation

private enum LinuxMetadataSource {
    case mounted(path: String)
    case archive(url: URL, index: LinuxArchiveIndex)
}

struct LinuxArchiveIndex {
    let topLevelEntries: Set<String>
    let releaseCandidates: [String]
}

struct LinuxImageMetadata {
    let sourcePath: String
    let sourceURL: URL
    let volumeName: String
    let topLevelEntries: Set<String>
    let diskInfo: String?
    let treeInfo: [String: [String: String]]
    let distroReleaseFields: [String: String]
    let archVersion: String?
    let grubHints: String
    let misoLabel: String?
    let evidence: [String]
}

extension AnalysisLogic {
    func readLinuxMetadata(fromMountPath mountPath: String, sourceURL: URL) -> LinuxImageMetadata {
        readLinuxMetadata(source: .mounted(path: mountPath), sourceURL: sourceURL)
    }

    func readLinuxMetadataFromArchive(sourceURL: URL) -> LinuxImageMetadata? {
        guard let archiveIndex = indexLinuxArchive(sourceURL: sourceURL),
              !archiveIndex.topLevelEntries.isEmpty else {
            self.log("bsdtar fallback: nie udało się odczytać listy plików archiwum: \(sourceURL.lastPathComponent)")
            return nil
        }

        return readLinuxMetadata(source: .archive(url: sourceURL, index: archiveIndex), sourceURL: sourceURL)
    }

    private func readLinuxMetadata(source: LinuxMetadataSource, sourceURL: URL) -> LinuxImageMetadata {
        let sourcePath: String
        let volumeName: String
        let topLevelEntries: Set<String>
        let textReader: (_ relativePath: String, _ maxBytes: Int) -> String?

        switch source {
        case .mounted(let mountPath):
            sourcePath = mountPath
            volumeName = URL(fileURLWithPath: mountPath).lastPathComponent
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: mountPath) {
                topLevelEntries = Set(entries)
            } else {
                topLevelEntries = []
            }
            textReader = { [weak self] relativePath, maxBytes in
                self?.readLinuxTextFile(fromMountPath: mountPath, relativePath: relativePath, maxBytes: maxBytes)
            }
        case .archive(let archiveURL, let archiveIndex):
            sourcePath = archiveURL.path
            volumeName = archiveURL.lastPathComponent
            topLevelEntries = archiveIndex.topLevelEntries
            textReader = { [weak self] relativePath, maxBytes in
                self?.readLinuxArchiveTextFile(sourceURL: archiveURL, relativePath: relativePath, maxBytes: maxBytes)
            }
        }

        var evidence: [String] = []

        let diskInfo = textReader(".disk/info", 64_000)?.singleLineCollapsed
        if diskInfo != nil {
            evidence.append(".disk/info")
        }

        var treeInfoSections: [String: [String: String]] = [:]
        var treeInfoPath: String?
        for candidate in [".treeinfo", "install/.treeinfo"] {
            if let content = textReader(candidate, 64_000) {
                treeInfoSections = parseLinuxINISections(content)
                treeInfoPath = candidate
                break
            }
        }
        if let treeInfoPath {
            evidence.append(treeInfoPath)
        }

        let distroRelease: (path: String?, fields: [String: String])
        switch source {
        case .mounted(let mountPath):
            distroRelease = readLinuxDistroReleaseFields(fromMountPath: mountPath)
        case .archive(_, let archiveIndex):
            distroRelease = readLinuxDistroReleaseFields(fromArchiveReleaseCandidates: archiveIndex.releaseCandidates, textReader: textReader)
        }
        if let releasePath = distroRelease.path {
            evidence.append(releasePath)
        }

        let archVersion = textReader("arch/version", 64_000)?.singleLineCollapsed
        if archVersion != nil {
            evidence.append("arch/version")
        }

        let grubHints = readLinuxGrubHints(textReader: textReader)
        if !grubHints.isEmpty {
            evidence.append("boot-config")
        }

        let misoLabel = extractFirstRegexMatch(
            pattern: #"misolabel=([A-Za-z0-9_\-\.]+)"#,
            in: grubHints,
            captureGroup: 1
        )
        if misoLabel != nil {
            evidence.append("misolabel")
        }

        return LinuxImageMetadata(
            sourcePath: sourcePath,
            sourceURL: sourceURL,
            volumeName: volumeName,
            topLevelEntries: topLevelEntries,
            diskInfo: diskInfo,
            treeInfo: treeInfoSections,
            distroReleaseFields: distroRelease.fields,
            archVersion: archVersion,
            grubHints: grubHints,
            misoLabel: misoLabel,
            evidence: evidence
        )
    }

    private func readLinuxDistroReleaseFields(fromMountPath mountPath: String) -> (path: String?, fields: [String: String]) {
        let distsURL = URL(fileURLWithPath: mountPath).appendingPathComponent("dists", isDirectory: true)
        let fm = FileManager.default

        guard fm.fileExists(atPath: distsURL.path),
              let entries = try? fm.contentsOfDirectory(at: distsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return (nil, [:])
        }

        let directories = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for directory in directories {
            let releaseURL = directory.appendingPathComponent("Release", isDirectory: false)
            guard let content = readLinuxTextFile(atAbsolutePath: releaseURL.path) else { continue }
            let fields = parseLinuxReleaseFields(content)
            if !fields.isEmpty {
                return ("dists/\(directory.lastPathComponent)/Release", fields)
            }
        }

        return (nil, [:])
    }

    private func readLinuxDistroReleaseFields(
        fromArchiveReleaseCandidates releaseCandidates: [String],
        textReader: (_ relativePath: String, _ maxBytes: Int) -> String?
    ) -> (path: String?, fields: [String: String]) {
        for candidate in releaseCandidates {
            guard let content = textReader(candidate, 64_000) else { continue }
            let fields = parseLinuxReleaseFields(content)
            if !fields.isEmpty {
                return (candidate, fields)
            }
        }

        return (nil, [:])
    }

    private func parseLinuxReleaseFields(_ content: String) -> [String: String] {
        var fields: [String: String] = [:]
        let allowedKeys = Set(["Origin", "Label", "Suite", "Version", "Codename", "Description", "Architectures"])

        for line in content.split(whereSeparator: \.isNewline) {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard allowedKeys.contains(key) else { continue }
            let valueStart = line.index(after: separatorIndex)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            fields[key] = value
        }

        return fields
    }

    private func parseLinuxINISections(_ content: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var currentSection = ""

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let valueStart = line.index(after: separatorIndex)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if result[currentSection] == nil {
                result[currentSection] = [:]
            }
            result[currentSection]?[key] = value
        }

        return result
    }

    private func readLinuxGrubHints(textReader: (_ relativePath: String, _ maxBytes: Int) -> String?) -> String {
        let candidates = [
            "boot/grub/grub.cfg",
            "boot/grub/loopback.cfg",
            "boot/grub2/grub.cfg",
            "EFI/BOOT/grub.cfg",
            "boot/grub/kernels.cfg",
            "boot/syslinux/syslinux.cfg",
            "boot/x86_64/loader/isolinux.cfg"
        ]

        let keywordList = [
            "menuentry",
            "gnu-linux",
            "rd.live.image",
            "boot=casper",
            "arch linux",
            "manjaro",
            "ubuntu",
            "xubuntu",
            "linux mint",
            "debian",
            "kali",
            "fedora",
            "almalinux",
            "opensuse",
            "pop_os",
            "pop-os",
            "misolabel",
            "archisobasedir"
        ]

        var snippets: [String] = []
        for candidate in candidates {
            guard let text = textReader(candidate, 160_000) else {
                continue
            }
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { line in
                    let lower = line.lowercased()
                    return keywordList.contains { lower.contains($0) }
                }
                .prefix(120)
            if !lines.isEmpty {
                snippets.append(lines.joined(separator: "\n"))
            }
        }

        return snippets.joined(separator: "\n")
    }

    private func readLinuxTextFile(fromMountPath mountPath: String, relativePath: String, maxBytes: Int = 64_000) -> String? {
        let absolutePath = URL(fileURLWithPath: mountPath)
            .appendingPathComponent(relativePath, isDirectory: false)
            .path
        return readLinuxTextFile(atAbsolutePath: absolutePath, maxBytes: maxBytes)
    }

    private func readLinuxTextFile(atAbsolutePath path: String, maxBytes: Int = 64_000) -> String? {
        guard FileManager.default.fileExists(atPath: path),
              let fileHandle = FileHandle(forReadingAtPath: path) else {
            return nil
        }

        defer {
            try? fileHandle.close()
        }

        let data = fileHandle.readData(ofLength: maxBytes)
        guard !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    var singleLineCollapsed: String {
        self
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
