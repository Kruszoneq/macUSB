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
    let evidence: [String]
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
        guard linuxImageLooksSupported(metadata) else {
            self.log("Brak wiarygodnych markerów Linuxa w obrazie: \(sourceURL.lastPathComponent)")
            return nil
        }

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
            evidence: deduplicatedEvidence
        )
    }

    private func linuxImageLooksSupported(_ metadata: LinuxImageMetadata) -> Bool {
        let lowerHints = metadata.grubHints.lowercased()
        let linuxKeywordSignal = [
            "gnu-linux",
            "rd.live.image",
            "boot=casper",
            "archisobasedir",
            "misolabel=",
            "linux mint",
            "ubuntu",
            "xubuntu",
            "debian",
            "kali",
            "fedora",
            "almalinux",
            "opensuse",
            "manjaro",
            "pop_os",
            "pop-os"
        ].contains { lowerHints.contains($0) }

        let topLevelSignals: Set<String> = [
            "arch",
            "manjaro",
            "casper",
            "dists",
            "liveos",
            "isolinux",
            "install",
            "ubuntu",
            "ubuntu-ports"
        ]

        let topLevelLower = Set(metadata.topLevelEntries.map { $0.lowercased() })
        let hasTopLevelSignal = !topLevelSignals.intersection(topLevelLower).isEmpty

        let strongMarkerCount = [
            metadata.diskInfo != nil,
            !metadata.treeInfo.isEmpty,
            metadata.archVersion != nil,
            !metadata.distroReleaseFields.isEmpty,
            metadata.misoLabel != nil,
            linuxKeywordSignal
        ].filter { $0 }.count

        if strongMarkerCount >= 1 && (hasTopLevelSignal || linuxKeywordSignal) {
            return true
        }

        let lowerVolumeName = metadata.volumeName.lowercased()
        let volumeSignal = [
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
            "mint",
            "pop_os",
            "pop-os"
        ].contains { lowerVolumeName.contains($0) }

        return strongMarkerCount >= 2 || (strongMarkerCount >= 1 && volumeSignal)
    }
}
