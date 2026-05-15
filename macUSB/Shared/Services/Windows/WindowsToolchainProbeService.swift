import Foundation

struct WindowsToolchainPresence {
    let hasHomebrew: Bool
    let hasWimlib: Bool
    let homebrewPath: String?
    let wimlibPath: String?
}

final class WindowsToolchainProbeService {
    static let shared = WindowsToolchainProbeService()
    private let probeQueue = DispatchQueue(label: "com.kruszoneq.macusb.windows.toolchain.probe")

    private init() {}

    func detectPresence() -> WindowsToolchainPresence {
        probeQueue.sync {
            let homebrewPath = resolveExecutablePath(named: "brew")
            let wimlibPath = resolveExecutablePath(named: "wimlib-imagex")

            return WindowsToolchainPresence(
                hasHomebrew: homebrewPath != nil,
                hasWimlib: wimlibPath != nil,
                homebrewPath: homebrewPath,
                wimlibPath: wimlibPath
            )
        }
    }

    private func resolveExecutablePath(named executable: String) -> String? {
        let fileManager = FileManager.default
        let fixedSearchRoots = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        for root in fixedSearchRoots {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent(executable).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"], !pathEnv.isEmpty {
            for root in pathEnv.split(separator: ":").map(String.init) {
                let candidate = URL(fileURLWithPath: root).appendingPathComponent(executable).path
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return runWhichExecutable(named: executable)
    }

    private func runWhichExecutable(named executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executable]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        let terminationGroup = DispatchGroup()
        terminationGroup.enter()
        process.terminationHandler = { _ in
            terminationGroup.leave()
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            return nil
        }

        terminationGroup.wait()
        process.terminationHandler = nil

        guard process.terminationStatus == 0 else {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        return output
    }
}
