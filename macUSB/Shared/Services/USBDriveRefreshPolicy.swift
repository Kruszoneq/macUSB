import Foundation

/// Main-thread policy: skip duplicate requests rather than queueing scans.
struct USBDriveRefreshPolicy {
    let interval: TimeInterval
    private(set) var isRunning = false
    private var lastStart: TimeInterval?

    init(interval: TimeInterval = 2.5) {
        self.interval = interval
    }

    mutating func begin(at now: TimeInterval, visible: Bool, active: Bool, force: Bool = false) -> Bool {
        guard visible, active, !isRunning else { return false }
        guard force || lastStart.map({ now - $0 >= interval }) ?? true else { return false }
        lastStart = now
        isRunning = true
        return true
    }

    mutating func finish() {
        isRunning = false
    }
}
