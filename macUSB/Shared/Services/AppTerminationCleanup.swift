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

        AppLogging.info("Rozpoczęto cleanup przed zamknięciem aplikacji.", category: "AppLifecycle")

        UserDefaults.standard.set(false, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        MenuState.shared.externalDrivesEnabled = false

        let tempRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macUSB_temp", isDirectory: true)
        if FileManager.default.fileExists(atPath: tempRootURL.path) {
            do {
                try FileManager.default.removeItem(at: tempRootURL)
                AppLogging.info(
                    "Zamknięcie aplikacji: usunięto katalog macUSB_temp.",
                    category: "Downloader"
                )
            } catch {
                AppLogging.error(
                    "Zamknięcie aplikacji: nie udało się usunąć macUSB_temp: \(error.localizedDescription)",
                    category: "Downloader"
                )
            }
        }

        InstallerSourceImageUnmountRegistry.shared.detachAllTrackedImagesOnAppTermination()
        AppLogging.info("Zakończono cleanup przed zamknięciem aplikacji.", category: "AppLifecycle")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
