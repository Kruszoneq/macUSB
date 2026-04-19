import Foundation

struct LinuxArchitectureMatch {
    let raw: String?
    let isARM: Bool
    let evidence: String?
}

extension AnalysisLogic {
    func normalizeLinuxArchitecture(from metadata: LinuxImageMetadata) -> LinuxArchitectureMatch {
        var candidates: [String] = []

        if let treeArch = metadata.treeInfo["general"]?["arch"] {
            candidates.append(treeArch)
        }

        if let treeReleaseArch = metadata.treeInfo["release"]?["arch"] {
            candidates.append(treeReleaseArch)
        }

        if let releaseArchitectures = metadata.distroReleaseFields["Architectures"] {
            candidates.append(contentsOf: releaseArchitectures.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init))
        }

        if let diskInfo = metadata.diskInfo {
            candidates.append(diskInfo)
        }

        candidates.append(metadata.volumeName)
        candidates.append(metadata.grubHints)

        for candidate in candidates {
            let lower = candidate.lowercased()
            if lower.contains("arm64") || lower.contains("aarch64") {
                return LinuxArchitectureMatch(raw: "arm64", isARM: true, evidence: "arch=arm64")
            }
            if lower.contains("armv8") {
                return LinuxArchitectureMatch(raw: "armv8", isARM: true, evidence: "arch=armv8")
            }
            if lower.contains("armv7") {
                return LinuxArchitectureMatch(raw: "armv7", isARM: true, evidence: "arch=armv7")
            }
            if lower.contains("armhf") {
                return LinuxArchitectureMatch(raw: "armhf", isARM: true, evidence: "arch=armhf")
            }
            if lower.contains(" arm ") || lower.hasPrefix("arm") {
                return LinuxArchitectureMatch(raw: "arm", isARM: true, evidence: "arch=arm")
            }
            if lower.contains("x86_64") {
                return LinuxArchitectureMatch(raw: "x86_64", isARM: false, evidence: "arch=x86_64")
            }
            if lower.contains("amd64") {
                return LinuxArchitectureMatch(raw: "amd64", isARM: false, evidence: "arch=amd64")
            }
            if lower.contains("i386") {
                return LinuxArchitectureMatch(raw: "i386", isARM: false, evidence: "arch=i386")
            }
            if lower.contains("i686") {
                return LinuxArchitectureMatch(raw: "i686", isARM: false, evidence: "arch=i686")
            }
        }

        return LinuxArchitectureMatch(raw: nil, isARM: false, evidence: nil)
    }
}
