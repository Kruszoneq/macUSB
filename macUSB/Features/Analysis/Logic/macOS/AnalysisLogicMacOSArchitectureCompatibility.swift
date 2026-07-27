import SwiftUI

enum MacOSArchitectureBlockReason: Equatable {
    case intelRequiresAppleSilicon
    case unknownCreateInstallMediaArchitecture
    case unknownHostArchitecture
}

extension MacOSArchitectureBlockReason {
    var titleLocalizationKey: String.LocalizationValue {
        switch self {
        case .intelRequiresAppleSilicon:
            return "analysis.macos.architecture.intel_incompatible.title"
        case .unknownCreateInstallMediaArchitecture, .unknownHostArchitecture:
            return "analysis.macos.architecture.unknown.title"
        }
    }

    var descriptionLocalizationKey: String.LocalizationValue {
        switch self {
        case .intelRequiresAppleSilicon:
            return "analysis.macos.architecture.intel_incompatible.description"
        case .unknownCreateInstallMediaArchitecture, .unknownHostArchitecture:
            return "analysis.macos.architecture.unknown.description"
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
            log("Architektura createinstallmedia: nie dotyczy (instalator bez createinstallmedia).")
            return true
        }

        let createInstallMediaInspection = inspection.createInstallMediaInspection
        let rawArchitectures = createInstallMediaInspection.rawArchitectures.isEmpty
            ? "brak"
            : createInstallMediaInspection.rawArchitectures.joined(separator: ", ")
        log(
            "Architektura createinstallmedia: \(createInstallMediaInspection.architecture.diagnosticLabel) [segmenty: \(rawArchitectures)]"
        )

        if let failureReason = createInstallMediaInspection.failureReason {
            logError("Nie udało się sklasyfikować architektury createinstallmedia: \(failureReason)")
        }

        guard createInstallMediaInspection.architecture != .unknown else {
            blockMacOSArchitectureCompatibility(reason: .unknownCreateInstallMediaArchitecture)
            return false
        }

        let hostArchitecture = MacHardwareArchitecture.current
        log("Architektura hosta dla analizy: \(hostArchitecture.diagnosticLabel)")

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
            log("Sprawdzenie Rosetty: \(rosettaAvailabilityDiagnosticLabel(availability))")
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
        isCapacitySufficient = false
        capacityCheckFinished = false
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
            showUnsupportedMessage = true
        }
        logError("Analiza zablokowana przez zgodność architektury: \(reason)")
        AppLogging.separator()
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
            return "dostępna"
        case .missing:
            return "niezainstalowana"
        case .indeterminate:
            return "stan niejednoznaczny"
        }
    }
}
