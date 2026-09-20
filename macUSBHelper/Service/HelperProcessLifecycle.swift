import Foundation
import Darwin
import os.log

final class HelperProcessLifecycle {
    static let shared = HelperProcessLifecycle()

    final class Lease {
        private let lock = NSLock()
        private var releaseHandler: (() -> Void)?

        init(releaseHandler: @escaping () -> Void) {
            self.releaseHandler = releaseHandler
        }

        func finish() {
            let handler = lock.withLock {
                let handler = releaseHandler
                releaseHandler = nil
                return handler
            }
            handler?()
        }

        deinit {
            finish()
        }
    }

    private enum LeaseKind: String {
        case connection
        case operation
    }

    private let queue = DispatchQueue(label: "macUSB.helper.process-lifecycle")
    private let log = OSLog(subsystem: "com.kruszoneq.macusb.helper", category: "Lifecycle")
    private let idleExitDelay: TimeInterval = 1
    private var activeConnections = 0
    private var activeOperations = 0
    private var exitGeneration: UInt = 0

    private init() {}

    func start() {
        queue.async {
            self.logState("Helper lifecycle started")
            self.scheduleExitIfIdle()
        }
    }

    func beginConnection() -> Lease {
        beginLease(kind: .connection)
    }

    func beginOperation() -> Lease {
        beginLease(kind: .operation)
    }

    private func beginLease(kind: LeaseKind) -> Lease {
        queue.sync {
            exitGeneration &+= 1
            switch kind {
            case .connection:
                activeConnections += 1
            case .operation:
                activeOperations += 1
            }
            logState("Lifecycle lease acquired: \(kind.rawValue)")
        }

        return Lease { [weak self] in
            self?.releaseLease(kind: kind)
        }
    }

    private func releaseLease(kind: LeaseKind) {
        queue.async {
            switch kind {
            case .connection:
                self.activeConnections = max(0, self.activeConnections - 1)
            case .operation:
                self.activeOperations = max(0, self.activeOperations - 1)
            }
            self.logState("Lifecycle lease released: \(kind.rawValue)")
            self.scheduleExitIfIdle()
        }
    }

    private func scheduleExitIfIdle() {
        guard activeConnections == 0, activeOperations == 0 else { return }

        exitGeneration &+= 1
        let scheduledGeneration = exitGeneration
        logState("Helper is idle; scheduling process exit")

        queue.asyncAfter(deadline: .now() + idleExitDelay) {
            guard scheduledGeneration == self.exitGeneration,
                  self.activeConnections == 0,
                  self.activeOperations == 0 else {
                return
            }

            self.logState("Helper is idle; exiting process")
            exit(EXIT_SUCCESS)
        }
    }

    private func logState(_ message: String) {
        os_log(
            "%{public}@ connections=%{public}d operations=%{public}d",
            log: log,
            type: .default,
            message,
            activeConnections,
            activeOperations
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
