import Foundation
import Darwin

struct FullDiskAccessProbe {
    private struct Candidate {
        let identifier: FullDiskAccessProbeIdentifier
        let url: URL
        let operation: FullDiskAccessProbeOperation
    }

    static func evaluate() -> FullDiskAccessEvaluation {
        let timeMachineResult = execute(
            Candidate(
                identifier: .timeMachine,
                url: URL(fileURLWithPath: "/Library/Preferences/com.apple.TimeMachine.plist"),
                operation: .readFile
            )
        )

        switch timeMachineResult.signal {
        case .granted:
            return FullDiskAccessEvaluation(status: .granted, results: [timeMachineResult])
        case .denied:
            return FullDiskAccessEvaluation(status: .denied, results: [timeMachineResult])
        case .unknown:
            break
        }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let fallbackCandidates = [
            Candidate(
                identifier: .mail,
                url: homeDirectory.appendingPathComponent("Library/Mail", isDirectory: true),
                operation: .listDirectory
            ),
            Candidate(
                identifier: .messages,
                url: homeDirectory.appendingPathComponent("Library/Messages", isDirectory: true),
                operation: .listDirectory
            ),
            Candidate(
                identifier: .safari,
                url: homeDirectory.appendingPathComponent("Library/Safari", isDirectory: true),
                operation: .listDirectory
            ),
            Candidate(
                identifier: .homeKit,
                url: homeDirectory.appendingPathComponent("Library/HomeKit", isDirectory: true),
                operation: .listDirectory
            )
        ]

        let fallbackResults = fallbackCandidates.map(execute)
        let allResults = [timeMachineResult] + fallbackResults

        if fallbackResults.contains(where: { $0.signal == .granted }) {
            return FullDiskAccessEvaluation(status: .granted, results: allResults)
        }
        if fallbackResults.contains(where: { $0.signal == .denied }) {
            return FullDiskAccessEvaluation(status: .denied, results: allResults)
        }
        return FullDiskAccessEvaluation(status: .unknown, results: allResults)
    }

    private static func execute(_ candidate: Candidate) -> FullDiskAccessProbeResult {
        switch candidate.operation {
        case .readFile:
            return readFile(candidate)
        case .listDirectory:
            return listDirectory(candidate)
        }
    }

    private static func readFile(_ candidate: Candidate) -> FullDiskAccessProbeResult {
        errno = 0
        let descriptor = open(candidate.url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            return failureResult(for: candidate, errnoCode: errno)
        }
        defer {
            close(descriptor)
        }

        var byte: UInt8 = 0
        errno = 0
        let readCount = withUnsafeMutablePointer(to: &byte) { pointer in
            Darwin.read(descriptor, pointer, 1)
        }
        guard readCount >= 0 else {
            return failureResult(for: candidate, errnoCode: errno)
        }

        return successResult(for: candidate)
    }

    private static func listDirectory(_ candidate: Candidate) -> FullDiskAccessProbeResult {
        errno = 0
        guard let directory = opendir(candidate.url.path) else {
            return failureResult(for: candidate, errnoCode: errno)
        }
        defer {
            closedir(directory)
        }

        errno = 0
        if readdir(directory) != nil || errno == 0 {
            return successResult(for: candidate)
        }
        return failureResult(for: candidate, errnoCode: errno)
    }

    private static func successResult(for candidate: Candidate) -> FullDiskAccessProbeResult {
        FullDiskAccessProbeResult(
            identifier: candidate.identifier,
            path: candidate.url.path,
            operation: candidate.operation,
            signal: .granted,
            errnoCode: nil,
            errorDescription: nil
        )
    }

    private static func failureResult(
        for candidate: Candidate,
        errnoCode: Int32
    ) -> FullDiskAccessProbeResult {
        FullDiskAccessProbeResult(
            identifier: candidate.identifier,
            path: candidate.url.path,
            operation: candidate.operation,
            signal: errnoCode == EPERM ? .denied : .unknown,
            errnoCode: errnoCode,
            errorDescription: errnoDescription(errnoCode)
        )
    }

    private static func errnoDescription(_ errnoCode: Int32) -> String {
        guard let description = strerror(errnoCode) else {
            return "Unknown error"
        }
        return String(cString: description)
    }
}
