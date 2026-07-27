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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = ["-archs", executableURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return MacOSCreateInstallMediaInspection(
                architecture: .unknown,
                rawArchitectures: [],
                failureReason: "lipo_launch_failed: \(error.localizedDescription)"
            )
        }

        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            return MacOSCreateInstallMediaInspection(
                architecture: .unknown,
                rawArchitectures: [],
                failureReason: "lipo_exit_\(process.terminationStatus): \(output)"
            )
        }

        let architectures = output
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let normalized = Set(architectures.map { $0.lowercased() })
        let containsAppleSilicon = normalized.contains("arm64") || normalized.contains("arm64e")
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
            rawArchitectures: architectures,
            failureReason: architecture == .unknown
                ? "unrecognized_architectures: \(output)"
                : nil
        )
    }
}
