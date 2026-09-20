import Foundation

@MainActor
final class MacOSDiskImageProcessRunner {
    private var activeProcess: Process?

    func run(arguments: [String]) async throws -> MacOSDiskImageProcessResult {
        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        let outputBuffer = MacOSDiskImageProcessOutputBuffer()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.appendStandardOutput(handle.availableData)
        }
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.appendStandardError(handle.availableData)
        }

        activeProcess = process
        defer {
            standardOutputPipe.fileHandleForReading.readabilityHandler = nil
            standardErrorPipe.fileHandleForReading.readabilityHandler = nil
            activeProcess = nil
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { terminatedProcess in
                    outputBuffer.appendStandardOutput(
                        standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
                    )
                    outputBuffer.appendStandardError(
                        standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
                    )
                    let snapshot = outputBuffer.snapshot()
                    continuation.resume(
                        returning: MacOSDiskImageProcessResult(
                            terminationStatus: terminatedProcess.terminationStatus,
                            standardOutput: snapshot.standardOutput,
                            standardError: snapshot.standardError
                        )
                    )
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    func cancel() {
        guard let activeProcess, activeProcess.isRunning else { return }
        activeProcess.terminate()
    }
}

private final class MacOSDiskImageProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutputData = Data()
    private var standardErrorData = Data()

    func appendStandardOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        standardOutputData.append(data)
        lock.unlock()
    }

    func appendStandardError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        standardErrorData.append(data)
        lock.unlock()
    }

    func snapshot() -> (standardOutput: String, standardError: String) {
        lock.lock()
        let outputData = standardOutputData
        let errorData = standardErrorData
        lock.unlock()
        return (
            String(data: outputData, encoding: .utf8) ?? "",
            String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}
