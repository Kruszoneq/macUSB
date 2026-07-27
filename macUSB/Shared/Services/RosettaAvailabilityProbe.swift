import Foundation

enum RosettaAvailability: Equatable {
    case available
    case missing
    case indeterminate
}

enum MacOSRosettaRequirement: Equatable {
    case notRequired
    case required(RosettaAvailability)

    var initialAvailability: RosettaAvailability? {
        guard case .required(let availability) = self else { return nil }
        return availability
    }
}

enum RosettaAvailabilityProbe {
    static func check() -> RosettaAvailability {
        guard MacHardwareArchitecture.current == .appleSilicon else {
            return .available
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            let description = error.localizedDescription.lowercased()
            if description.contains("bad cpu type") || (error as NSError).code == 86 {
                return .missing
            }
            return .indeterminate
        }

        if process.terminationStatus == 0 {
            return .available
        }

        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).lowercased()

        if process.terminationStatus == 86 || output.contains("bad cpu type") {
            return .missing
        }
        return .indeterminate
    }
}
