import Foundation

struct LinuxDistributionMatch {
    let distro: String?
    let version: String?
    let edition: String?
    let evidence: String
}

extension AnalysisLogic {
    func classifyLinuxDistribution(from metadata: LinuxImageMetadata) -> LinuxDistributionMatch {
        let volumeLower = metadata.volumeName.lowercased()
        let diskInfo = metadata.diskInfo ?? ""
        let diskInfoLower = diskInfo.lowercased()
        let hintsLower = metadata.grubHints.lowercased()

        let treeRelease = metadata.treeInfo["release"] ?? [:]
        let treeGeneral = metadata.treeInfo["general"] ?? [:]
        let treeReleaseName = treeRelease["name"]?.lowercased() ?? ""
        let treeReleaseVersion = treeRelease["version"]
        let treeGeneralFamily = treeGeneral["family"]?.lowercased() ?? ""
        let treeGeneralName = treeGeneral["name"]?.lowercased() ?? ""
        let treeGeneralVersion = treeGeneral["version"]

        let releaseFields = metadata.distroReleaseFields
        let releaseOriginLower = (releaseFields["Origin"] ?? "").lowercased()
        let releaseLabelLower = (releaseFields["Label"] ?? "").lowercased()
        let releaseCodenameLower = (releaseFields["Codename"] ?? "").lowercased()

        // openSUSE Leap
        if treeReleaseName.contains("opensuse leap") || treeGeneralFamily.contains("opensuse leap") || treeGeneralName.contains("opensuse leap") || volumeLower.contains("leap") {
            let version = firstNonEmpty([
                treeReleaseVersion,
                treeGeneralVersion,
                extractFirstVersion(in: metadata.volumeName)
            ])
            return LinuxDistributionMatch(
                distro: "openSUSE Leap",
                version: version,
                edition: "Installer",
                evidence: "rule=opensuse_leap"
            )
        }

        // openSUSE Tumbleweed (rolling)
        if treeReleaseName.contains("opensuse tumbleweed") || treeGeneralFamily.contains("opensuse tumbleweed") || treeGeneralName.contains("opensuse tumbleweed") || volumeLower.contains("tumbleweed") {
            return LinuxDistributionMatch(
                distro: "openSUSE Tumbleweed",
                version: nil,
                edition: "DVD",
                evidence: "rule=opensuse_tumbleweed"
            )
        }

        // Pop!_OS
        if diskInfoLower.contains("pop_os") || diskInfoLower.contains("pop os") || hintsLower.contains("pop_os") || hintsLower.contains("pop-os") || volumeLower.contains("pop_os") || volumeLower.contains("pop os") {
            let version = firstNonEmpty([
                extractFirstVersion(in: diskInfo),
                releaseFields["Version"],
                extractFirstVersion(in: metadata.volumeName)
            ])
            return LinuxDistributionMatch(
                distro: "Pop!_OS",
                version: version,
                edition: "Live",
                evidence: "rule=pop_os"
            )
        }

        // Xubuntu (must be before Ubuntu)
        if diskInfoLower.hasPrefix("xubuntu") || volumeLower.contains("xubuntu") || hintsLower.contains("xubuntu") {
            let version = firstNonEmpty([
                extractFirstVersion(in: diskInfo),
                releaseFields["Version"],
                extractFirstVersion(in: metadata.volumeName)
            ])
            return LinuxDistributionMatch(
                distro: "Xubuntu",
                version: version,
                edition: "Desktop",
                evidence: "rule=xubuntu"
            )
        }

        // Ubuntu
        if diskInfoLower.hasPrefix("ubuntu") || volumeLower.contains("ubuntu") || hintsLower.contains("try or install ubuntu") {
            let version = firstNonEmpty([
                extractFirstVersion(in: diskInfo),
                releaseFields["Version"],
                extractFirstVersion(in: metadata.volumeName)
            ])
            return LinuxDistributionMatch(
                distro: "Ubuntu",
                version: version,
                edition: "Desktop",
                evidence: "rule=ubuntu"
            )
        }

        // Linux Mint
        if diskInfoLower.contains("linux mint") || volumeLower.contains("linux mint") || hintsLower.contains("start linux mint") {
            let version = firstNonEmpty([
                extractFirstVersion(in: diskInfo),
                releaseFields["Version"],
                extractFirstVersion(in: metadata.volumeName)
            ])
            let edition = extractFirstRegexMatch(
                pattern: #"linux mint\s+[0-9A-Za-z\._]+\s+([A-Za-z]+)"#,
                in: diskInfoLower,
                captureGroup: 1
            )?.capitalized
            return LinuxDistributionMatch(
                distro: "Linux Mint",
                version: normalizedVersion(version),
                edition: edition,
                evidence: "rule=linux_mint"
            )
        }

        // Debian
        if diskInfoLower.contains("debian gnu/linux") || (releaseOriginLower == "debian" && (volumeLower.contains("debian") || hintsLower.contains("debian"))) {
            let version = firstNonEmpty([
                extractFirstVersion(in: diskInfo),
                releaseFields["Version"],
                extractFirstVersion(in: metadata.volumeName)
            ])
            let edition = diskInfoLower.contains("netinst") ? "NETINST" : nil
            return LinuxDistributionMatch(
                distro: "Debian",
                version: normalizedVersion(version),
                edition: edition,
                evidence: "rule=debian"
            )
        }

        // Kali
        if diskInfoLower.contains("kali gnu/linux") || releaseCodenameLower == "kali-rolling" || volumeLower.contains("kali") || hintsLower.contains("kali") {
            let version = firstNonEmpty([
                extractFirstVersion(in: diskInfo),
                extractFirstVersion(in: metadata.volumeName)
            ])
            return LinuxDistributionMatch(
                distro: "Kali Linux",
                version: normalizedVersion(version),
                edition: nil,
                evidence: "rule=kali"
            )
        }

        // Arch
        if metadata.archVersion != nil || (metadata.topLevelEntries.contains("arch") && (hintsLower.contains("arch linux") || hintsLower.contains("archisobasedir"))) {
            return LinuxDistributionMatch(
                distro: "Arch Linux",
                version: metadata.archVersion,
                edition: "Install medium",
                evidence: "rule=arch"
            )
        }

        // Manjaro
        let topLevelLower = Set(metadata.topLevelEntries.map { $0.lowercased() })
        let hasManjaroSignal = (metadata.misoLabel?.uppercased().contains("MANJARO") ?? false) || topLevelLower.contains("manjaro") || hintsLower.contains("manjaro")
        if hasManjaroSignal {
            let miso = metadata.misoLabel ?? ""
            let versionFromLabel = extractManjaroVersion(fromMisoLabel: miso)
            let editionFromLabel = extractManjaroEdition(fromMisoLabel: miso)
            return LinuxDistributionMatch(
                distro: "Manjaro",
                version: firstNonEmpty([versionFromLabel, extractFirstVersion(in: metadata.volumeName)]),
                edition: editionFromLabel,
                evidence: "rule=manjaro"
            )
        }

        // AlmaLinux
        if volumeLower.contains("almalinux") || hintsLower.contains("almalinux") {
            let version = firstNonEmpty([
                extractFirstVersion(in: metadata.volumeName),
                extractFirstVersion(in: metadata.grubHints)
            ])
            let edition = extractFirstRegexMatch(
                pattern: #"almalinux-[0-9_\.]+-[a-z0-9_]+-([A-Za-z0-9_]+)"#,
                in: metadata.volumeName.lowercased(),
                captureGroup: 1
            )?.replacingOccurrences(of: "_", with: " ").uppercased()
            return LinuxDistributionMatch(
                distro: "AlmaLinux",
                version: normalizedVersion(version),
                edition: edition,
                evidence: "rule=almalinux"
            )
        }

        // Fedora
        if volumeLower.contains("fedora") || hintsLower.contains("fedora-workstation-live") || releaseLabelLower.contains("fedora") {
            let version = firstNonEmpty([
                extractFirstRegexMatch(pattern: #"fedora[^0-9]*([0-9]+(?:\.[0-9]+)*)"#, in: metadata.volumeName.lowercased(), captureGroup: 1),
                extractFirstVersion(in: metadata.grubHints),
                extractFirstVersion(in: metadata.volumeName)
            ])
            let edition: String? = (volumeLower.contains("ws-live") || hintsLower.contains("workstation-live")) ? "Workstation Live" : nil
            return LinuxDistributionMatch(
                distro: "Fedora",
                version: normalizedVersion(version),
                edition: edition,
                evidence: "rule=fedora"
            )
        }

        return LinuxDistributionMatch(
            distro: nil,
            version: nil,
            edition: nil,
            evidence: "rule=linux_unrecognized"
        )
    }

    private func extractManjaroVersion(fromMisoLabel label: String) -> String? {
        guard let token = extractFirstRegexMatch(
            pattern: #"MANJARO_[A-Z]+_([0-9]{4})"#,
            in: label.uppercased(),
            captureGroup: 1
        ) else {
            return nil
        }

        guard token.count == 4 else { return token }
        let major = token.prefix(2)
        let minor = token.suffix(2)
        return "\(major).\(minor)"
    }

    private func extractManjaroEdition(fromMisoLabel label: String) -> String? {
        extractFirstRegexMatch(
            pattern: #"MANJARO_([A-Z]+)_[0-9]{4}"#,
            in: label.uppercased(),
            captureGroup: 1
        )
    }

    func extractFirstRegexMatch(pattern: String, in text: String, captureGroup: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              captureGroup < match.numberOfRanges,
              let range = Range(match.range(at: captureGroup), in: text) else {
            return nil
        }

        return String(text[range])
    }

    private func extractFirstVersion(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let token = extractFirstRegexMatch(
            pattern: #"\b[0-9]+(?:[\._][0-9]+)*\b"#,
            in: text
        )
        return normalizedVersion(token)
    }

    private func normalizedVersion(_ value: String?) -> String? {
        guard let value else { return nil }
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasSuffix(".iso") {
            trimmed = String(trimmed.dropLast(4))
        } else if lower.hasSuffix(".cdr") {
            trimmed = String(trimmed.dropLast(4))
        }
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "_", with: ".")
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values.first(where: { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? nil
    }
}
