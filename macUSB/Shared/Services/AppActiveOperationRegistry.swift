import Foundation
import Combine

enum AppActiveOperationKind: String, CaseIterable {
    case analysis
    case usbCreation
    case downloader
    case rosettaInstallation
    case helperRepair
    case helperActivity
    case cleanup
    case usbEject
}

struct AppActiveOperationSnapshot: Identifiable {
    let id: UUID
    let kind: AppActiveOperationKind
    let context: String
    let startedAt: Date
}

final class AppActiveOperationToken {
    private let lock = NSLock()
    private weak var registry: AppActiveOperationRegistry?
    private var operationID: UUID?

    fileprivate init(registry: AppActiveOperationRegistry, operationID: UUID) {
        self.registry = registry
        self.operationID = operationID
    }

    func finish() {
        let operationID: UUID? = lock.withLock {
            defer { self.operationID = nil }
            return self.operationID
        }
        guard let operationID else { return }
        registry?.finish(operationID: operationID)
    }

    deinit {
        finish()
    }
}

final class AppActiveOperationRegistry: ObservableObject {
    static let shared = AppActiveOperationRegistry()

    @Published private(set) var activeOperationCount = 0

    private let lock = NSLock()
    private var operations: [UUID: AppActiveOperationSnapshot] = [:]

    var hasActiveOperations: Bool {
        lock.withLock { !operations.isEmpty }
    }

    private init() {}

    @discardableResult
    func begin(kind: AppActiveOperationKind, context: String) -> AppActiveOperationToken {
        let operation = AppActiveOperationSnapshot(
            id: UUID(),
            kind: kind,
            context: normalizedContext(context),
            startedAt: Date()
        )
        let count = lock.withLock {
            operations[operation.id] = operation
            return operations.count
        }
        publishActiveOperationCount(count)
        AppLogging.info(
            "Rozpoczęto chronioną operację [kind=\(kind.rawValue), context=\(operation.context), id=\(operation.id.uuidString)].",
            category: "AppLifecycle"
        )
        return AppActiveOperationToken(registry: self, operationID: operation.id)
    }

    func snapshot() -> [AppActiveOperationSnapshot] {
        lock.withLock {
            operations.values.sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.startedAt < rhs.startedAt
            }
        }
    }

    fileprivate func finish(operationID: UUID) {
        let result: (operation: AppActiveOperationSnapshot?, count: Int) = lock.withLock {
            let operation = operations.removeValue(forKey: operationID)
            return (operation, operations.count)
        }
        publishActiveOperationCount(result.count)
        guard let operation = result.operation else { return }
        let duration = max(0, Date().timeIntervalSince(operation.startedAt))
        AppLogging.info(
            String(
                format: "Zakończono chronioną operację [kind=%@, context=%@, id=%@, duration=%.2fs].",
                operation.kind.rawValue,
                operation.context,
                operation.id.uuidString,
                duration
            ),
            category: "AppLifecycle"
        )
    }

    private func publishActiveOperationCount(_ count: Int) {
        if Thread.isMainThread {
            activeOperationCount = count
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                activeOperationCount = lock.withLock { self.operations.count }
            }
        }
    }

    private func normalizedContext(_ context: String) -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unspecified" : trimmed
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
