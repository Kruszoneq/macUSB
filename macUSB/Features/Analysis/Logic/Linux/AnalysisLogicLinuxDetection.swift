import Foundation

struct LinuxDetectionResult {
    let isLinux: Bool
    let isDistributionRecognized: Bool
    let distro: String?
    let version: String?
    let edition: String?
    let archRaw: String?
    let isARM: Bool
    let displayName: String
    let gateSignals: [String]
    let classificationRule: String
    let matchedSignal: String?
    let versionSource: String?
    let evidence: [String]
}

private struct LinuxGateDecision {
    let isSupported: Bool
    let gateSignals: [String]
}

extension AnalysisLogic {
    func detectLinux(fromMountPath mountPath: String, sourceURL: URL) -> LinuxDetectionResult? {
        let metadata = readLinuxMetadata(fromMountPath: mountPath, sourceURL: sourceURL)
        return detectLinux(fromMetadata: metadata, sourceURL: sourceURL)
    }

    func detectLinuxFromArchive(sourceURL: URL) -> LinuxDetectionResult? {
        guard let metadata = readLinuxMetadataFromArchive(sourceURL: sourceURL) else {
            self.log("Brak możliwości odczytu zawartości ISO przez bsdtar: \(sourceURL.lastPathComponent)")
            return nil
        }
        return detectLinux(fromMetadata: metadata, sourceURL: sourceURL)
    }

    private func detectLinux(fromMetadata metadata: LinuxImageMetadata, sourceURL: URL) -> LinuxDetectionResult? {
        let gateDecision = linuxImageSupportDecision(metadata)
        guard gateDecision.isSupported else {
            self.log("Brak wiarygodnych markerów Linuxa w obrazie: \(sourceURL.lastPathComponent)")
            return nil
        }
        self.log("Linux gate_signals: \(gateDecision.gateSignals.sorted().joined(separator: ", "))")

        let classification = classifyLinuxDistribution(from: metadata)
        let architecture = normalizeLinuxArchitecture(from: metadata)
        let displayName = buildLinuxDisplayName(
            distro: classification.distro,
            version: classification.version,
            isARM: architecture.isARM
        )

        var evidence = metadata.evidence
        evidence.append(classification.evidence)
        if let architectureEvidence = architecture.evidence {
            evidence.append(architectureEvidence)
        }

        let deduplicatedEvidence = Array(Set(evidence)).sorted()

        return LinuxDetectionResult(
            isLinux: true,
            isDistributionRecognized: classification.distro != nil,
            distro: classification.distro,
            version: classification.version,
            edition: classification.edition,
            archRaw: architecture.raw,
            isARM: architecture.isARM,
            displayName: displayName,
            gateSignals: gateDecision.gateSignals.sorted(),
            classificationRule: classification.classificationRule,
            matchedSignal: classification.matchedSignal,
            versionSource: classification.versionSource,
            evidence: deduplicatedEvidence
        )
    }

    private func linuxImageSupportDecision(_ metadata: LinuxImageMetadata) -> LinuxGateDecision {
        let lowerHints = metadata.grubHints.lowercased()
        var gateSignals: Set<String> = []

        let linuxKeywordSignals = [
            "gnu-linux",
            "rd.live.image",
            "rd.live.dir=",
            "boot=casper",
            "archisobasedir",
            "misolabel=",
            "misobasedir=",
            "root=miso:",
            "linux mint",
            "ubuntu",
            "xubuntu",
            "debian",
            "kali",
            "fedora",
            "almalinux",
            "opensuse",
            "manjaro",
            "nixos",
            "garuda",
            "gentoo",
            "pop_os",
            "pop-os"
        ]
        for signal in linuxKeywordSignals where lowerHints.contains(signal) {
            gateSignals.insert("hint:\(signal)")
        }

        let topLevelSignals: Set<String> = [
            "arch",
            "manjaro",
            "casper",
            "dists",
            "liveos",
            "isolinux",
            "install",
            "ubuntu",
            "ubuntu-ports",
            ".miso",
            "garuda",
            "nix-store.squashfs"
        ]

        let topLevelLower = Set(metadata.topLevelEntries.map { $0.lowercased() })
        let matchedTopLevelSignals = topLevelSignals.intersection(topLevelLower)
        if !matchedTopLevelSignals.isEmpty {
            matchedTopLevelSignals.forEach { gateSignals.insert("top-level:\($0)") }
        }
        let hasTopLevelSignal = !matchedTopLevelSignals.isEmpty

        if metadata.hasBootConfigWithLinuxKernel {
            gateSignals.insert("boot-config:menuentry+linux")
        }

        let strongMarkerCount = [
            metadata.diskInfo != nil,
            !metadata.treeInfo.isEmpty,
            metadata.archVersion != nil,
            metadata.versionTxt != nil,
            !metadata.distroReleaseFields.isEmpty,
            metadata.misoLabel != nil,
            !metadata.readmeHints.isEmpty,
            !matchedTopLevelSignals.isEmpty,
            metadata.hasBootConfigWithLinuxKernel,
            !gateSignals.isEmpty
        ].filter { $0 }.count

        if strongMarkerCount >= 1 && (hasTopLevelSignal || !gateSignals.isEmpty || metadata.hasBootConfigWithLinuxKernel) {
            return LinuxGateDecision(isSupported: true, gateSignals: Array(gateSignals))
        }

        let lowerVolumeName = metadata.volumeName.lowercased()
        let volumeSignals = [
            "linux",
            "ubuntu",
            "xubuntu",
            "debian",
            "kali",
            "fedora",
            "almalinux",
            "arch",
            "manjaro",
            "opensuse",
            "nixos",
            "garuda",
            "gentoo",
            "mint",
            "pop_os",
            "pop-os"
        ]
        let matchedVolumeSignals = volumeSignals.filter { lowerVolumeName.contains($0) }
        matchedVolumeSignals.forEach { gateSignals.insert("volume:\($0)") }
        let volumeSignal = !matchedVolumeSignals.isEmpty

        let isSupported = strongMarkerCount >= 2 || (strongMarkerCount >= 1 && volumeSignal) || metadata.hasBootConfigWithLinuxKernel
        return LinuxGateDecision(isSupported: isSupported, gateSignals: Array(gateSignals))
    }
}
