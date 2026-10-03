import Foundation
import Darwin

final class USBDiscoveryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handler: (() -> Void)?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let callback = handler
        lock.unlock()
        callback?()
    }

    fileprivate func observe(_ callback: (() -> Void)?) {
        lock.lock()
        handler = callback
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { callback?() }
    }
}

/// Read-only discovery only. A stuck child keeps its slot until exit is observed.
final class USBDiscoveryProcessRunner: @unchecked Sendable {
    static let shared = USBDiscoveryProcessRunner()

    enum Failure: Error, Equatable {
        case busy, cancelled, timedOut, outputLimit, launchFailed, readFailed
        case exitStatus(Int32)
    }

    private final class Session: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var started = false
        private var cancelled = false
        var finished = false // Protected by the runner lock.

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func didStart() {
            lock.lock()
            started = true
            let shouldTerminate = cancelled
            lock.unlock()
            if shouldTerminate, process.isRunning { process.terminate() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let shouldTerminate = started
            lock.unlock()
            if shouldTerminate, process.isRunning { process.terminate() }
        }

        func killIfRunning() {
            lock.lock()
            let canKill = started
            lock.unlock()
            if canKill, process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        }
    }

    private let lock = NSLock()
    private var active: Session?
    private var isShuttingDown = false
    private let executableURL: URL
    private let timeout: TimeInterval
    private let terminationGrace: TimeInterval
    private let maximumOutputBytes: Int

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/sbin/diskutil"),
        timeout: TimeInterval = 5,
        terminationGrace: TimeInterval = 0.5,
        maximumOutputBytes: Int = 4 * 1024 * 1024
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.terminationGrace = terminationGrace
        self.maximumOutputBytes = maximumOutputBytes
    }

    func run(arguments: [String], cancellation: USBDiscoveryCancellation? = nil) -> Result<Data, Failure> {
        let session = Session()
        lock.lock()
        guard !isShuttingDown, active == nil else {
            let failure: Failure = isShuttingDown ? .cancelled : .busy
            lock.unlock()
            return .failure(failure)
        }
        active = session
        lock.unlock()

        defer { finish(session) }
        cancellation?.observe { [weak session] in session?.cancel() }
        defer { cancellation?.observe(nil) }
        guard !session.isCancelled else { return .failure(.cancelled) }

        let output = Pipe()
        let errors = Pipe()
        let handles = [output.fileHandleForReading, output.fileHandleForWriting,
                       errors.fileHandleForReading, errors.fileHandleForWriting]
        defer { handles.forEach { try? $0.close() } }
        let process = session.process
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self, weak session] _ in
            if let session { self?.releaseFinished(session) }
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        do { try process.run() } catch { return .failure(.launchFailed) }
        session.didStart()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()

        let descriptors = [output.fileHandleForReading.fileDescriptor, errors.fileHandleForReading.fileDescriptor]
        guard descriptors.allSatisfy({ fcntl($0, F_SETFL, fcntl($0, F_GETFL) | O_NONBLOCK) != -1 }) else {
            session.cancel()
            session.killIfRunning()
            return .failure(.readFailed)
        }

        var streams = [Data(), Data()]
        var ended = [false, false]
        var failure: Failure?
        var stoppingAt: TimeInterval?
        var didKill = false
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if session.isCancelled, failure == nil { failure = .cancelled }
            if now - startedAt >= timeout, failure == nil { failure = .timedOut }
            if failure != nil, stoppingAt == nil {
                stoppingAt = now
                session.cancel()
            }
            if let stoppingAt, now - stoppingAt >= terminationGrace, !didKill {
                session.killIfRunning()
                didKill = true
            }
            if let stoppingAt, now - stoppingAt >= terminationGrace * 2 {
                // Foundation observes/reaps exit asynchronously. Retain exclusion if
                // even SIGKILL cannot finish an uninterruptible kernel operation.
                return .failure(failure ?? .timedOut)
            }

            var polls = descriptors.enumerated().map { index, fd in
                pollfd(fd: ended[index] ? -1 : fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            }
            let ready = polls.withUnsafeMutableBufferPointer { Darwin.poll($0.baseAddress, 2, 25) }
            if ready < 0, errno != EINTR { failure = .readFailed }
            for index in 0..<2 where !ended[index] && polls[index].revents != 0 {
                let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptors[index], $0.baseAddress, $0.count) }
                if count > 0 {
                    if streams[index].count + count <= maximumOutputBytes {
                        streams[index].append(contentsOf: bytes.prefix(count))
                    } else if failure == nil {
                        failure = .outputLimit
                    }
                } else if count == 0 {
                    ended[index] = true
                } else if errno != EAGAIN && errno != EINTR {
                    ended[index] = true
                    failure = failure ?? .readFailed
                }
            }
            if !process.isRunning, ended.allSatisfy({ $0 }) {
                process.waitUntilExit()
                if let failure { return .failure(failure) }
                guard process.terminationStatus == 0 else { return .failure(.exitStatus(process.terminationStatus)) }
                return .success(streams[0])
            }
        }
    }

    func shutdown() {
        lock.lock()
        isShuttingDown = true
        let session = active
        lock.unlock()
        session?.cancel()
        guard let session else { return }
        let deadline = ProcessInfo.processInfo.systemUptime + terminationGrace
        while isActive(session), ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
        session.killIfRunning()
        let cleanupDeadline = ProcessInfo.processInfo.systemUptime + terminationGrace
        while isActive(session), ProcessInfo.processInfo.systemUptime < cleanupDeadline { usleep(10_000) }
    }

    private func isActive(_ session: Session) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active === session
    }

    private func finish(_ session: Session) {
        lock.lock()
        session.finished = true
        lock.unlock()
        releaseFinished(session)
    }

    private func releaseFinished(_ session: Session) {
        lock.lock()
        defer { lock.unlock() }
        guard active === session, session.finished, !session.process.isRunning else { return }
        session.process.terminationHandler = nil
        active = nil
    }
}
