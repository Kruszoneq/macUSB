import Foundation

/// Uniwersalna blokada usypiania systemu dla długich procesów aplikacji.
///
/// Dziala referencyjnie: pierwszy aktywny token wlacza blokade idle sleep,
/// ostatni zwolniony token ja zdejmuje.
final class SystemSleepBlocker {
    static let shared = SystemSleepBlocker()

    private let lock = NSLock()
    private var activeTokens: Set<UUID> = []
    private var activity: NSObjectProtocol?
    private var activeReason: String = ""

    private init() {}

    @discardableResult
    func begin(reason: String) -> UUID {
        let token = UUID()
        lock.lock()
        defer { lock.unlock() }

        let shouldStart = activeTokens.isEmpty
        activeTokens.insert(token)

        guard shouldStart else { return token }

        activeReason = reason
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
        AppLogging.info("Sleep blocker: aktywacja (\(reason))", category: "Power")
        return token
    }

    func end(_ token: UUID) {
        lock.lock()
        defer { lock.unlock() }

        guard activeTokens.remove(token) != nil else { return }
        guard activeTokens.isEmpty else { return }

        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
            AppLogging.info("Sleep blocker: dezaktywacja (\(activeReason))", category: "Power")
        }
        activeReason = ""
    }
}
