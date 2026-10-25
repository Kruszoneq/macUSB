import Foundation

/// Per-analysis bounded change history. Unchanged outcomes remain quiet for
/// the entire session; suppressed counts are reported on change or recovery.
final class USBDiscoveryDiagnostics: @unchecked Sendable {
    private struct Entry {
        var signature: String
        var suppressed: Int = 0
    }

    /// Ordered presentation and admission state, excluding confirmation times,
    /// scan generations, process identifiers and command durations.
    private struct SnapshotState: Equatable {
        struct Target: Equatable {
            let drive: USBDrive
            let identity: String?
            let capacity: Result<Int64, USBDiscoveryProblem>?
        }
        let physical: [Target]
        let option: [Target]
        let issues: [USBDiscoveryIssue]
        let allowExternal: Bool

        var description: String {
            func describe(_ target: Target) -> String {
                let drive = target.drive
                return "{device=\(drive.device), name=\(drive.name), url=\(drive.url.path), size=\(drive.size), media=\(drive.mediaDisplayName), partition=\(drive.partitionScheme?.rawValue ?? "unknown"), format=\(drive.fileSystemFormat?.rawValue ?? "unknown"), needsFormatting=\(drive.needsFormatting), identity=\(target.identity ?? "unknown"), capacity=\(String(describing: target.capacity))}"
            }
            return "AllowExternalDrives=\(allowExternal), physical=[\(physical.map(describe).joined(separator: ", "))], Option=[\(option.map(describe).joined(separator: ", "))], issues=\(issues)"
        }

        init(_ snapshot: USBDiscoverySnapshot) {
            func target(_ drive: USBDrive) -> Target {
                let proof = snapshot.verification[drive.selectionID]
                return Target(drive: drive, identity: proof?.identity, capacity: proof?.capacity)
            }
            physical = snapshot.physicalDrives.map(target)
            option = snapshot.optionDrives.map(target)
            issues = snapshot.issues.sorted {
                ($0.device, String(describing: $0.problem)) < ($1.device, String(describing: $1.problem))
            }
            allowExternal = snapshot.allowExternalDrives
        }
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var lastSnapshot: SnapshotState?

    func recordSnapshot(_ snapshot: USBDiscoverySnapshot, message: String, workflow: AppLogging.Workflow?, force: Bool = false) {
        let state = SnapshotState(snapshot)
        lock.lock()
        let changed = lastSnapshot != state
        lastSnapshot = state
        let recovering = entries["scan.result"].map { $0.signature != "snapshot" } ?? false
        lock.unlock()
        record(message + " State: \(state.description).", key: "scan.result", signature: "snapshot", workflow: workflow, force: force || changed || recovering)
    }

    /// Successful queries and ordinary process cleanup are silent until an
    /// error previously recorded for that exact operation has recovered.
    func recover(_ message: String, key: String, workflow: AppLogging.Workflow?) {
        lock.lock()
        let needsRecovery = entries[key].map { $0.signature != "recovered" } ?? false
        lock.unlock()
        guard needsRecovery else { return }
        record(message, key: key, signature: "recovered", workflow: workflow)
    }

    func record(
        _ message: String, key: String, signature: String,
        workflow: AppLogging.Workflow?, force: Bool = false
    ) {
        lock.lock()
        let previous = entries[key]
        if !force, var previous, previous.signature == signature {
            previous.suppressed += 1
            entries[key] = previous
            lock.unlock()
            return
        }
        // Device identifiers can accumulate after hot-plugging; bound history.
        if entries.count >= 256, entries[key] == nil { entries.removeAll() }
        entries[key] = Entry(signature: signature)
        lock.unlock()
        let summary = previous.map { $0.suppressed > 0 ? " Repeated occurrences suppressed: \($0.suppressed)." : "" } ?? ""
        AppLogging.info(message + summary, stage: .usb, workflow: workflow)
    }
}
