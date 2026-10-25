import SwiftUI

enum MacOSArchitectureBlockReason: Equatable {
    case intelRequiresAppleSilicon
    case unknownCreateInstallMediaArchitecture
    case unknownHostArchitecture
}

extension MacOSArchitectureBlockReason {
    var titleLocalizationResource: LocalizedStringResource {
        switch self {
        case .intelRequiresAppleSilicon:
            return LocalizedStringResource("analysis.macos.architecture.intel_incompatible.title", table: "Analysis")
        case .unknownCreateInstallMediaArchitecture, .unknownHostArchitecture:
            return LocalizedStringResource("analysis.macos.architecture.unknown.title", table: "Analysis")
        }
    }

    var descriptionLocalizationResource: LocalizedStringResource {
        switch self {
        case .intelRequiresAppleSilicon:
            return LocalizedStringResource("analysis.macos.architecture.intel_incompatible.description", table: "Analysis")
        case .unknownCreateInstallMediaArchitecture, .unknownHostArchitecture:
            return LocalizedStringResource("analysis.macos.architecture.unknown.description", table: "Analysis")
        }
    }
}

extension AnalysisLogic {
    @discardableResult
    func applyMacOSArchitecturePreflight(
        inspection: MacOSInstallerAppInspection,
        name: String,
        rawVersion: String
    ) -> Bool {
        createInstallMediaInspection = inspection.createInstallMediaInspection
        macOSArchitectureBlockReason = nil
        macOSRosettaRequirement = .notRequired

        guard inspection.hasCreateinstallmedia else {
            logMacOS("createinstallmedia architecture: not applicable (installer has no createinstallmedia).")
            return true
        }

        let createInstallMediaInspection = inspection.createInstallMediaInspection
        let rawArchitectures = createInstallMediaInspection.rawArchitectures.isEmpty
            ? "none"
            : createInstallMediaInspection.rawArchitectures.joined(separator: ", ")
        logMacOS(
            "createinstallmedia architecture: \(createInstallMediaInspection.architecture.diagnosticLabel) [segments: \(rawArchitectures)]"
        )

        if let failureReason = createInstallMediaInspection.failureReason {
            logMacOSError("Failed to classify createinstallmedia architecture: \(failureReason)")
        }

        guard createInstallMediaInspection.architecture != .unknown else {
            blockMacOSArchitectureCompatibility(reason: .unknownCreateInstallMediaArchitecture)
            return false
        }

        let hostArchitecture = MacHardwareArchitecture.current
        logMacOS("Host architecture for analysis: \(hostArchitecture.diagnosticLabel)")

        guard hostArchitecture != .unknown else {
            blockMacOSArchitectureCompatibility(reason: .unknownHostArchitecture)
            return false
        }

        if hostArchitecture == .intel,
           createInstallMediaInspection.architecture == .appleSilicon {
            blockMacOSArchitectureCompatibility(reason: .intelRequiresAppleSilicon)
            return false
        }

        if hostArchitecture == .appleSilicon,
           createInstallMediaInspection.architecture == .intel,
           requiresRosettaForLegacyCreateInstallMedia(name: name, rawVersion: rawVersion) {
            let availability = RosettaAvailabilityProbe.check()
            macOSRosettaRequirement = .required(availability)
            logMacOS("Rosetta check: \(rosettaAvailabilityDiagnosticLabel(availability))")
        }

        return true
    }

    private func blockMacOSArchitectureCompatibility(reason: MacOSArchitectureBlockReason) {
        macOSArchitectureBlockReason = reason
        macOSRosettaRequirement = .notRequired
        isSystemDetected = false
        showUSBSection = false
        selectedDrive = nil
        selectedDriveSelectionID = nil
        usbTargetReadiness = .noSelection
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
            showUnsupportedMessage = true
        }
        logMacOSError("Analysis blocked by architecture compatibility: \(reason)")
        AppLogging.separator(stage: .analysis, workflow: isPPC ? .ppc : .macos)
    }

    private func requiresRosettaForLegacyCreateInstallMedia(name: String, rawVersion: String) -> Bool {
        guard let majorVersion = legacyMarketingVersion(name: name, rawVersion: rawVersion) else {
            return false
        }
        return (10...15).contains(majorVersion)
    }

    private func legacyMarketingVersion(name: String, rawVersion: String) -> Int? {
        let lowercasedName = name.lowercased()
        let mappings: [(String, Int)] = [
            ("yosemite", 10),
            ("el capitan", 11),
            ("sierra", 12),
            ("high sierra", 13),
            ("mojave", 14),
            ("catalina", 15)
        ]
        if let match = mappings.first(where: { lowercasedName.contains($0.0) }) {
            return match.1
        }

        if rawVersion.hasPrefix("10.10") { return 10 }
        if rawVersion.hasPrefix("10.11") { return 11 }
        if rawVersion.hasPrefix("10.12") { return 12 }
        if rawVersion.hasPrefix("10.13") { return 13 }
        if rawVersion.hasPrefix("10.14") { return 14 }
        if rawVersion.hasPrefix("10.15") { return 15 }

        if lowercasedName.contains("sierra") && !lowercasedName.contains("high") {
            return 12
        }
        return nil
    }

    private func rosettaAvailabilityDiagnosticLabel(_ availability: RosettaAvailability) -> String {
        switch availability {
        case .available:
            return "available"
        case .missing:
            return "missing"
        case .indeterminate:
            return "indeterminate"
        }
    }
}
