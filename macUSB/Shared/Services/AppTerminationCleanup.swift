import Foundation

final class AppTerminationCleanup {
    static let shared = AppTerminationCleanup()

    private let lock = NSLock()
    private var didPerformCleanup = false

    private init() {}

    func performIfNeeded() {
        let shouldPerform = lock.withLock {
            guard !didPerformCleanup else { return false }
            didPerformCleanup = true
            return true
        }
        guard shouldPerform else { return }

        let cleanupToken = AppActiveOperationRegistry.shared.begin(
            kind: .cleanup,
            context: "app_termination"
        )
        defer { cleanupToken.finish() }

        AppLogging.info("Application termination cleanup started.", stage: .app)

        UserDefaults.standard.set(false, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        MenuState.shared.externalDrivesEnabled = false

        let tempRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macUSB_temp", isDirectory: true)
        if FileManager.default.fileExists(atPath: tempRootURL.path) {
            do {
                try FileManager.default.removeItem(at: tempRootURL)
                AppLogging.info(
                    "Application termination: removed macUSB_temp directory.",
                    stage: .app
                )
            } catch {
                AppLogging.error(
                    "Application termination: could not remove macUSB_temp: \(error.localizedDescription)",
                    stage: .app
                )
            }
        }

        InstallerSourceImageUnmountRegistry.shared.detachAllTrackedImagesOnAppTermination()
        PrivilegedOperationClient.shared.disconnectForAppTermination()
        AppLogging.info("Application termination cleanup completed.", stage: .app)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
