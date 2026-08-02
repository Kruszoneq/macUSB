import CoreFoundation
import Foundation

enum MacOSCreateInstallMediaArchitecture: Equatable {
    case appleSilicon
    case intel
    case universal
    case unknown
    case notApplicable

    var diagnosticLabel: String {
        switch self {
        case .appleSilicon:
            return "Apple Silicon"
        case .intel:
            return "Intel"
        case .universal:
            return "Uniwersalne (Apple Silicon, Intel)"
        case .unknown:
            return "Nieznana"
        case .notApplicable:
            return "Nie dotyczy"
        }
    }
}

struct MacOSCreateInstallMediaInspection: Equatable {
    let architecture: MacOSCreateInstallMediaArchitecture
    let rawArchitectures: [String]
    let failureReason: String?

    static let notApplicable = MacOSCreateInstallMediaInspection(
        architecture: .notApplicable,
        rawArchitectures: [],
        failureReason: nil
    )
}

enum MacOSCreateInstallMediaArchitectureInspector {
    static func inspect(executableURL: URL) -> MacOSCreateInstallMediaInspection {
        guard let cpuTypes = CFBundleCopyExecutableArchitecturesForURL(
            executableURL as CFURL
        ) as? [NSNumber],
        !cpuTypes.isEmpty else {
            return MacOSCreateInstallMediaInspection(
                architecture: .unknown,
                rawArchitectures: [],
                failureReason: "core_foundation_architecture_inspection_failed"
            )
        }

        let rawArchitectures = uniqueArchitectureNames(
            cpuTypes.map { architectureName(for: $0.intValue) }
        )
        let normalized = Set(rawArchitectures)
        let containsAppleSilicon = normalized.contains("arm64")
        let containsIntel = normalized.contains("x86_64")

        let architecture: MacOSCreateInstallMediaArchitecture
        switch (containsAppleSilicon, containsIntel) {
        case (true, true):
            architecture = .universal
        case (true, false):
            architecture = .appleSilicon
        case (false, true):
            architecture = .intel
        case (false, false):
            architecture = .unknown
        }

        return MacOSCreateInstallMediaInspection(
            architecture: architecture,
            rawArchitectures: rawArchitectures,
            failureReason: architecture == .unknown
                ? "unsupported_architectures: \(rawArchitectures.joined(separator: ", "))"
                : nil
        )
    }

    private static func architectureName(for cpuType: Int) -> String {
        switch cpuType {
        case kCFBundleExecutableArchitectureX86_64:
            return "x86_64"
        case kCFBundleExecutableArchitectureARM64:
            // arm64e uses the same CPU type and follows the same compatibility policy.
            return "arm64"
        default:
            return String(
                format: "cpu_0x%08x",
                UInt32(truncatingIfNeeded: cpuType)
            )
        }
    }

    private static func uniqueArchitectureNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
