import Foundation
import Darwin

enum MacHardwareArchitecture: Equatable {
    case appleSilicon
    case intel
    case unknown

    static let current: MacHardwareArchitecture = detect()

    var diagnosticLabel: String {
        switch self {
        case .appleSilicon:
            return "Apple Silicon (ARM64)"
        case .intel:
            return "Intel (x86_64)"
        case .unknown:
            return "Nieznana"
        }
    }

    private static func detect() -> MacHardwareArchitecture {
        var arm64Capability: Int32 = 0
        var arm64CapabilitySize = MemoryLayout<Int32>.size
        if sysctlbyname(
            "hw.optional.arm64",
            &arm64Capability,
            &arm64CapabilitySize,
            nil,
            0
        ) == 0, arm64Capability == 1 {
            return .appleSilicon
        }

        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else {
            return .unknown
        }

        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        switch machine.lowercased() {
        case "arm64", "arm64e":
            return .appleSilicon
        case "x86_64":
            return .intel
        default:
            return .unknown
        }
    }
}
