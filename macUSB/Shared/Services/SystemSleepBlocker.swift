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
    private var activeLoggingStage: AppLogging.Stage?
    private var activeLoggingWorkflow: AppLogging.Workflow?

    private init() {}

    @discardableResult
    func begin(
        reason: String,
        loggingStage: AppLogging.Stage,
        loggingWorkflow: AppLogging.Workflow
    ) -> UUID {
        let token = UUID()
        lock.lock()
        defer { lock.unlock() }

        let shouldStart = activeTokens.isEmpty
        activeTokens.insert(token)

        guard shouldStart else { return token }

        activeReason = reason
        activeLoggingStage = loggingStage
        activeLoggingWorkflow = loggingWorkflow
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
        AppLogging.info(
            "Idle sleep prevention activated: reason=\(reason).",
            stage: loggingStage,
            workflow: loggingWorkflow
        )
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
            if let activeLoggingStage, let activeLoggingWorkflow {
                AppLogging.info(
                    "Idle sleep prevention released: reason=\(activeReason).",
                    stage: activeLoggingStage,
                    workflow: activeLoggingWorkflow
                )
            }
        }
        activeReason = ""
        activeLoggingStage = nil
        activeLoggingWorkflow = nil
    }
}
