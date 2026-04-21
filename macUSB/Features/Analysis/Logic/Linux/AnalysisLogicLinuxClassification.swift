import Foundation

struct LinuxDistributionMatch {
    let distro: String?
    let version: String?
    let edition: String?
    let evidence: String
}

private struct LinuxCatalogDetectionRule {
    let distro: String
    let evidence: String
    let signals: [String]
    let edition: String?
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

        if let genericMatch = classifyLinuxDistributionFromCatalog(
            metadata: metadata,
            volumeLower: volumeLower,
            diskInfoLower: diskInfoLower,
            hintsLower: hintsLower,
            treeReleaseName: treeReleaseName,
            treeGeneralFamily: treeGeneralFamily,
            treeGeneralName: treeGeneralName,
            releaseOriginLower: releaseOriginLower,
            releaseLabelLower: releaseLabelLower,
            releaseCodenameLower: releaseCodenameLower,
            releaseFields: releaseFields
        ) {
            return genericMatch
        }

        return LinuxDistributionMatch(
            distro: nil,
            version: nil,
            edition: nil,
            evidence: "rule=linux_unrecognized"
        )
    }

    private func classifyLinuxDistributionFromCatalog(
        metadata: LinuxImageMetadata,
        volumeLower: String,
        diskInfoLower: String,
        hintsLower: String,
        treeReleaseName: String,
        treeGeneralFamily: String,
        treeGeneralName: String,
        releaseOriginLower: String,
        releaseLabelLower: String,
        releaseCodenameLower: String,
        releaseFields: [String: String]
    ) -> LinuxDistributionMatch? {
        let topLevelLower = metadata.topLevelEntries.map { $0.lowercased() }.joined(separator: " ")
        let misoLower = (metadata.misoLabel ?? "").lowercased()
        let releaseFieldsLower = releaseFields
            .map { "\($0.key.lowercased()) \($0.value.lowercased())" }
            .joined(separator: " ")
        let corpus = [
            volumeLower,
            diskInfoLower,
            hintsLower,
            treeReleaseName,
            treeGeneralFamily,
            treeGeneralName,
            releaseOriginLower,
            releaseLabelLower,
            releaseCodenameLower,
            topLevelLower,
            misoLower,
            releaseFieldsLower
        ].joined(separator: " | ")

        let rules: [LinuxCatalogDetectionRule] = [
            .init(distro: "Alpine Linux", evidence: "rule=linux_catalog_alpine", signals: ["alpine linux", "alpine"], edition: nil),
            .init(distro: "antiX", evidence: "rule=linux_catalog_antix", signals: ["antix", "anti x"], edition: nil),
            .init(distro: "ArcoLinux", evidence: "rule=linux_catalog_arco", signals: ["arcolinux", "arco linux"], edition: nil),
            .init(distro: "Artix Linux", evidence: "rule=linux_catalog_artix", signals: ["artix linux", "artix"], edition: nil),
            .init(distro: "BlueStar Linux", evidence: "rule=linux_catalog_bluestar", signals: ["bluestar", "blue star"], edition: nil),
            .init(distro: "Bodhi Linux", evidence: "rule=linux_catalog_bodhi", signals: ["bodhi linux", "bodhi"], edition: nil),
            .init(distro: "BunsenLabs", evidence: "rule=linux_catalog_bunsenlabs", signals: ["bunsenlabs", "bunsen labs"], edition: nil),
            .init(distro: "Clear Linux", evidence: "rule=linux_catalog_clear", signals: ["clear linux", "clearlinux"], edition: nil),
            .init(distro: "Deepin", evidence: "rule=linux_catalog_deepin", signals: ["deepin"], edition: nil),
            .init(distro: "elementary OS", evidence: "rule=linux_catalog_elementary", signals: ["elementary os", "elementary"], edition: nil),
            .init(distro: "EndeavourOS", evidence: "rule=linux_catalog_endeavour", signals: ["endeavouros", "endeavour os"], edition: nil),
            .init(distro: "Endless OS", evidence: "rule=linux_catalog_endless", signals: ["endless os"], edition: nil),
            .init(distro: "Feren OS", evidence: "rule=linux_catalog_feren", signals: ["feren os", "feren"], edition: nil),
            .init(distro: "Gentoo", evidence: "rule=linux_catalog_gentoo", signals: ["gentoo"], edition: nil),
            .init(distro: "KaOS", evidence: "rule=linux_catalog_kaos", signals: ["kaos"], edition: nil),
            .init(distro: "Knoppix", evidence: "rule=linux_catalog_knoppix", signals: ["knoppix"], edition: nil),
            .init(distro: "Kubuntu", evidence: "rule=linux_catalog_kubuntu", signals: ["kubuntu"], edition: nil),
            .init(distro: "Linux Lite", evidence: "rule=linux_catalog_lite", signals: ["linux lite"], edition: nil),
            .init(distro: "Lubuntu", evidence: "rule=linux_catalog_lubuntu", signals: ["lubuntu"], edition: nil),
            .init(distro: "Mageia", evidence: "rule=linux_catalog_mageia", signals: ["mageia"], edition: nil),
            .init(distro: "MX Linux", evidence: "rule=linux_catalog_mx", signals: ["mx linux"], edition: nil),
            .init(distro: "KDE neon", evidence: "rule=linux_catalog_neon", signals: ["kde neon", "neon"], edition: nil),
            .init(distro: "Netrunner", evidence: "rule=linux_catalog_netrunner", signals: ["netrunner"], edition: nil),
            .init(distro: "NixOS", evidence: "rule=linux_catalog_nixos", signals: ["nixos", "nix os"], edition: nil),
            .init(distro: "OpenMandriva", evidence: "rule=linux_catalog_openmandriva", signals: ["openmandriva", "open mandriva"], edition: nil),
            .init(distro: "Parrot OS", evidence: "rule=linux_catalog_parrot", signals: ["parrot os", "parrot security"], edition: nil),
            .init(distro: "PCLinuxOS", evidence: "rule=linux_catalog_pclinuxos", signals: ["pclinuxos", "pc linux os"], edition: nil),
            .init(distro: "Peppermint OS", evidence: "rule=linux_catalog_peppermint", signals: ["peppermint os", "peppermint"], edition: nil),
            .init(distro: "Qubes OS", evidence: "rule=linux_catalog_qubes", signals: ["qubes os", "qubes"], edition: nil),
            .init(distro: "Raspberry Pi OS", evidence: "rule=linux_catalog_raspios", signals: ["raspberry pi os", "raspios", "raspian"], edition: nil),
            .init(distro: "RebornOS", evidence: "rule=linux_catalog_rebornos", signals: ["rebornos", "reborn os"], edition: nil),
            .init(distro: "Red Hat Enterprise Linux", evidence: "rule=linux_catalog_redhat", signals: ["red hat enterprise linux", "red hat", "redhat", "rhel"], edition: nil),
            .init(distro: "ROSA", evidence: "rule=linux_catalog_rosa", signals: ["rosa linux", "rosa"], edition: nil),
            .init(distro: "Septor Linux", evidence: "rule=linux_catalog_septor", signals: ["septor linux", "septor"], edition: nil),
            .init(distro: "Slackware", evidence: "rule=linux_catalog_slackware", signals: ["slackware"], edition: nil),
            .init(distro: "Solus", evidence: "rule=linux_catalog_solus", signals: ["solus"], edition: nil),
            .init(distro: "Tails", evidence: "rule=linux_catalog_tails", signals: ["tails"], edition: nil),
            .init(distro: "Tiny Core Linux", evidence: "rule=linux_catalog_tinycore", signals: ["tiny core linux", "tinycore"], edition: nil),
            .init(distro: "Ubuntu Cinnamon", evidence: "rule=linux_catalog_ubuntu_cinnamon", signals: ["ubuntu cinnamon"], edition: nil),
            .init(distro: "Ubuntu DDE", evidence: "rule=linux_catalog_ubuntu_dde", signals: ["ubuntu dde"], edition: nil),
            .init(distro: "Ubuntu MATE", evidence: "rule=linux_catalog_ubuntu_mate", signals: ["ubuntu mate"], edition: nil),
            .init(distro: "Void Linux", evidence: "rule=linux_catalog_void", signals: ["void linux"], edition: nil),
            .init(distro: "Zorin OS", evidence: "rule=linux_catalog_zorin", signals: ["zorin os", "zorin"], edition: nil)
        ]

        for rule in rules {
            guard let matchedSignal = firstMatchedLinuxSignal(in: corpus, signals: rule.signals) else { continue }
            let version = firstNonEmpty([
                releaseFields["Version"],
                extractFirstVersion(in: metadata.diskInfo ?? ""),
                extractFirstVersion(in: metadata.volumeName),
                extractFirstVersion(in: metadata.grubHints)
            ])

            return LinuxDistributionMatch(
                distro: rule.distro,
                version: normalizedVersion(version),
                edition: rule.edition,
                evidence: "\(rule.evidence):\(matchedSignal)"
            )
        }

        return nil
    }

    private func firstMatchedLinuxSignal(in corpus: String, signals: [String]) -> String? {
        for signal in signals {
            let normalizedSignal = signal.lowercased()
            if normalizedSignal.contains(" ") {
                if corpus.contains(normalizedSignal) {
                    return normalizedSignal
                }
                continue
            }

            let escaped = NSRegularExpression.escapedPattern(for: normalizedSignal)
            let pattern = #"(?<![a-z0-9])\#(escaped)(?![a-z0-9])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(corpus.startIndex..<corpus.endIndex, in: corpus)
            if regex.firstMatch(in: corpus, options: [], range: range) != nil {
                return normalizedSignal
            }
        }

        return nil
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
