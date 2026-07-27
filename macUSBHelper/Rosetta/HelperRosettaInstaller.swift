import Foundation
import Darwin
import os.log

enum HelperRosettaInstaller {
    private static let maximumDiagnosticCharacters = 4_000

    static func validateEnvironment() throws {
        guard geteuid() == 0 else {
            throw NSError(
                domain: "macUSBHelper",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Instalacja Rosetty wymaga działania helpera jako root."]
            )
        }

        var arm64Capability: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &arm64Capability, &size, nil, 0) == 0,
              arm64Capability == 1 else {
            throw NSError(
                domain: "macUSBHelper",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Rosettę można instalować wyłącznie na Macu z układem scalonym Apple."]
            )
        }
    }

    static func run() -> RosettaInstallationResultPayload {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = ["--install-rosetta", "--agree-to-license"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        os_log(
            "Rosetta installation started: /usr/sbin/softwareupdate --install-rosetta --agree-to-license",
            type: .default
        )

        do {
            try process.run()
        } catch {
            let diagnostic = boundedDiagnostic(error.localizedDescription)
            os_log("Rosetta installation launch failed: %{public}@", type: .error, diagnostic)
            return RosettaInstallationResultPayload(
                success: false,
                terminationStatus: -1,
                diagnosticMessage: diagnostic
            )
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnostic = output.isEmpty ? nil : boundedDiagnostic(output)
        let success = process.terminationReason == .exit && process.terminationStatus == 0

        os_log(
            "Rosetta installation finished: success=%{public}@ status=%{public}d",
            type: success ? .default : .error,
            success ? "true" : "false",
            process.terminationStatus
        )
        if let diagnostic {
            os_log("Rosetta installation output tail: %{public}@", type: .default, diagnostic)
        }

        return RosettaInstallationResultPayload(
            success: success,
            terminationStatus: process.terminationStatus,
            diagnosticMessage: diagnostic
        )
    }

    private static func boundedDiagnostic(_ value: String) -> String {
        guard value.count > maximumDiagnosticCharacters else { return value }
        return String(value.suffix(maximumDiagnosticCharacters))
    }
}
