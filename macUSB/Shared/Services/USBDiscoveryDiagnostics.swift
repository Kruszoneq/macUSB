import Foundation

/// Per-analysis bounded diagnostic history. Repeated polls are summarized once
/// per minute; the first occurrence, changes and recovery are always recorded.
final class USBDiscoveryDiagnostics: @unchecked Sendable {
    private struct Entry {
        var signature: String
        var lastEmission: TimeInterval
        var suppressed: Int = 0
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func record(
        _ message: String, key: String, signature: String,
        workflow: AppLogging.Workflow?, force: Bool = false
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let previous = entries[key]
        if !force, var previous, previous.signature == signature, now - previous.lastEmission < 60 {
            previous.suppressed += 1
            entries[key] = previous
            lock.unlock()
            return
        }
        // Device identifiers can accumulate after hot-plugging; bound history.
        if entries.count >= 256, entries[key] == nil { entries.removeAll() }
        entries[key] = Entry(signature: signature, lastEmission: now)
        lock.unlock()
        let summary = previous.map { $0.suppressed > 0 ? " Repeated occurrences suppressed: \($0.suppressed)." : "" } ?? ""
        AppLogging.info(message + summary, stage: .usb, workflow: workflow)
    }
}
