import Foundation

extension AnalysisLogic {
    func classifyWindowsImage(from metadata: WindowsImageMetadata) -> WindowsDetectionResult? {
        guard let family = classifyWindowsFamily(from: metadata) else {
            return nil
        }

        let arch = normalizeWindowsArchitecture(from: metadata)
        let servicePack = extractWindowsServicePack(family: family, metadata: metadata)

        let isFamilySupported = family.supportsWorkflow
        let hasEFI = metadata.efiStatus.hasEFI
        let isSupported = isFamilySupported && hasEFI
        let supportReason: WindowsSupportReason
        switch (isFamilySupported, hasEFI) {
        case (true, true): supportReason = .supported
        case (false, true): supportReason = .unsupportedFamily
        case (true, false): supportReason = .missingEFI
        case (false, false): supportReason = .unsupportedFamilyAndMissingEFI
        }

        var displayName = "\(family.displayPrefix) \(family.displayVersionLabel)"
        if let servicePack {
            let servicePackNumber = servicePack.uppercased().replacingOccurrences(of: "SP", with: "")
            displayName += " - Service Pack \(servicePackNumber)"
        }
        if arch == .arm {
            displayName += " (ARM)"
        }

        var evidence = metadata.evidence
        evidence.append("family:\(family.rawValue)")
        evidence.append("arch:\(arch.rawValue)")
        if let servicePack {
            evidence.append("service-pack:\(servicePack)")
        } else {
            evidence.append("service-pack:none")
        }
        evidence.append("support-reason:\(supportReason.rawValue)")

        return WindowsDetectionResult(
            family: family,
            servicePack: servicePack,
            arch: arch,
            isARM: arch == .arm,
            displayName: displayName,
            isSupported: isSupported,
            supportReason: supportReason,
            efiStatus: metadata.efiStatus,
            evidence: Array(Set(evidence)).sorted()
        )
    }

    private func classifyWindowsFamily(from metadata: WindowsImageMetadata) -> WindowsFamily? {
        if let serverFamily = classifyWindowsServerFamily(from: metadata) {
            return serverFamily
        }

        let branch = metadata.buildBranch?.lowercased() ?? ""
        let volume = metadata.volumeName.lowercased()

        if !metadata.win51Markers.isEmpty || (metadata.hasI386 && branch.isEmpty && !metadata.hasInstallImage) {
            return .xp
        }

        if branch.contains("lh_sp") || branch.contains("vista") {
            return .vista
        }

        if branch.contains("win7") {
            return .seven
        }

        if branch.contains("winblue") {
            return .eightOne
        }

        if branch.contains("win8") {
            return .eight
        }

        if branch.contains("vb_release") {
            return .ten
        }

        if branch.contains("ge_release") {
            return .eleven
        }

        if volume.contains("gsp1") || volume.contains("win7") {
            return .seven
        }
        if volume.contains("winvista") || volume.contains("vista") {
            return .vista
        }
        if volume.contains("grtmpfpp") || volume.contains("win51") {
            return .xp
        }
        if volume.contains("winblue") || volume.contains("ir5_ccsa") {
            return .eightOne
        }
        if volume.contains("win8") || volume.contains("hrm_ccsa") {
            return .eight
        }

        if let minClient = metadata.cversionMinClient?.lowercased() {
            if minClient.hasPrefix("7601") {
                return .seven
            }
            if minClient.hasPrefix("8508") {
                return .eight
            }
        }

        return nil
    }

    private func classifyWindowsServerFamily(from metadata: WindowsImageMetadata) -> WindowsFamily? {
        let branch = metadata.buildBranch?.lowercased() ?? ""
        let volume = metadata.volumeName.lowercased()
        let fileName = metadata.sourceFileName.lowercased()
        let minServer = metadata.cversionMinServer?.lowercased() ?? ""

        let hasServerHint =
            fileName.contains("server") ||
            volume.contains("server") ||
            volume.contains("sss") ||
            volume.contains("grmsxfrer") ||
            volume.contains("crmefpp") ||
            volume.contains("ir5_sss")

        if hasServerHint && !metadata.win51Markers.isEmpty && metadata.hasI386 {
            return .server2003
        }

        if hasServerHint && branch.contains("win7sp1") {
            return .server2008R2
        }

        if hasServerHint && branch.contains("winblue") {
            return .server2012R2
        }

        if hasServerHint && branch.contains("win8") {
            return .server2012
        }

        if hasServerHint && branch.contains("rs1_release") {
            return .server2016
        }

        if hasServerHint && branch.contains("rs5_release") {
            return .server2019
        }

        if hasServerHint && branch.contains("fe_release") {
            return .server2022
        }

        if hasServerHint && branch.contains("ge_release") {
            return .server2025
        }

        if hasServerHint {
            if fileName.contains("2008 r2") || volume.contains("grmsxfrer") || minServer.hasPrefix("7601") {
                return .server2008R2
            }
            if fileName.contains("2012 r2") || volume.contains("ir5_sss") {
                return .server2012R2
            }
            if fileName.contains("2012") {
                return .server2012
            }
            if fileName.contains("2016") || branch.contains("rs1") {
                return .server2016
            }
            if fileName.contains("2019") || branch.contains("rs5") {
                return .server2019
            }
            if fileName.contains("2022") || branch.contains("fe_release") {
                return .server2022
            }
            if fileName.contains("2025") || branch.contains("ge_release") {
                return .server2025
            }
            if fileName.contains("2003") || volume.contains("crmefpp") {
                return .server2003
            }
        }

        return nil
    }

    private func normalizeWindowsArchitecture(from metadata: WindowsImageMetadata) -> WindowsArchitecture {
        let candidates = [
            metadata.buildArchRaw ?? "",
            metadata.efiStatus.evidence.joined(separator: " ")
        ].joined(separator: " ").lowercased()

        if candidates.contains("arm64") || candidates.contains("aarch64") || candidates.contains("bootaa64") {
            return .arm
        }
        if candidates.contains("amd64") || candidates.contains("x86_64") || candidates.contains("x86") || metadata.hasI386 {
            return .x86
        }
        return .unknown
    }

    private func extractWindowsServicePack(family: WindowsFamily, metadata: WindowsImageMetadata) -> String? {
        switch family {
        case .xp:
            if let marker = metadata.win51Markers.first(where: { $0.uppercased().contains(".SP") }),
               let range = marker.uppercased().range(of: ".SP") {
                let suffix = marker[range.upperBound...]
                let digits = suffix.prefix { $0.isNumber }
                if !digits.isEmpty {
                    return "SP\(digits)"
                }
            }
            return nil
        case .vista, .seven:
            let branch = metadata.buildBranch?.lowercased() ?? ""
            if branch.contains("sp3") { return "SP3" }
            if branch.contains("sp2") { return "SP2" }
            if branch.contains("sp1") { return "SP1" }
            return nil
        case .server2003:
            if let marker = metadata.win51Markers.first(where: { $0.uppercased().contains(".SP") }),
               let range = marker.uppercased().range(of: ".SP") {
                let suffix = marker[range.upperBound...]
                let digits = suffix.prefix { $0.isNumber }
                if !digits.isEmpty {
                    return "SP\(digits)"
                }
            }
            return nil
        case .server2008R2:
            let branch = metadata.buildBranch?.lowercased() ?? ""
            if branch.contains("sp1") {
                return "SP1"
            }
            return nil
        case .server2012, .server2012R2, .server2016, .server2019, .server2022, .server2025, .eight, .eightOne, .ten, .eleven:
            return nil
        }
    }
}
