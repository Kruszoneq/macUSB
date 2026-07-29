import Foundation

final class MacOSLocalInstallerProcessRunner: @unchecked Sendable {
    enum CancellationPolicy: Sendable, Equatable {
        case terminateProcess
        case ignoreCancellation
    }

    private final class ProcessState: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var started = false
        private var cancelled = false

        func register(_ process: Process) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else {
                return false
            }
            self.process = process
            return true
        }

        func markStarted() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            started = true
            return cancelled
        }

        func cancel() {
            let processToTerminate: Process?
            lock.lock()
            cancelled = true
            processToTerminate = started ? process : nil
            lock.unlock()

            if processToTerminate?.isRunning == true {
                processToTerminate?.terminate()
            }
        }

        func finish() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            process = nil
            started = false
            return cancelled
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private final class ErrorBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ newData: Data) {
            lock.lock()
            data = newData
            lock.unlock()
        }

        var string: String {
            lock.lock()
            let snapshot = data
            lock.unlock()
            return String(data: snapshot, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    func run(
        executableURL: URL,
        arguments: [String],
        cancellationPolicy: CancellationPolicy = .terminateProcess
    ) async throws -> MacOSLocalInstallerProcessResult {
        let state = ProcessState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<MacOSLocalInstallerProcessResult, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    if cancellationPolicy == .terminateProcess, state.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    let process = Process()
                    let standardError = Pipe()
                    let errorBuffer = ErrorBuffer()
                    let readerGroup = DispatchGroup()

                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = standardError

                    guard state.register(process) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    readerGroup.enter()
                    DispatchQueue.global(qos: .utility).async {
                        errorBuffer.store(
                            standardError.fileHandleForReading.readDataToEndOfFile()
                        )
                        readerGroup.leave()
                    }

                    do {
                        try process.run()
                        standardError.fileHandleForWriting.closeFile()

                        if state.markStarted(),
                           cancellationPolicy == .terminateProcess,
                           process.isRunning {
                            process.terminate()
                        }

                        process.waitUntilExit()
                        readerGroup.wait()
                        let wasCancelled = state.finish()

                        if wasCancelled, cancellationPolicy == .terminateProcess {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(
                                returning: MacOSLocalInstallerProcessResult(
                                    standardError: errorBuffer.string,
                                    terminationStatus: process.terminationStatus
                                )
                            )
                        }
                    } catch {
                        standardError.fileHandleForWriting.closeFile()
                        readerGroup.wait()
                        let wasCancelled = state.finish()
                        if wasCancelled, cancellationPolicy == .terminateProcess {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            if cancellationPolicy == .terminateProcess {
                state.cancel()
            }
        }
    }
}
