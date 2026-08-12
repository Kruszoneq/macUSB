import Foundation
import Combine

final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var skipAnalysisEnabled: Bool = false
    @Published var skipLinuxManualSelectionEnabled: Bool = false
    @Published var externalDrivesEnabled: Bool = UserDefaults.standard.bool(forKey: "AllowExternalDrives")
    @Published var notificationsEnabled: Bool = false
    @Published var hasFullDiskAccess: Bool = true
    @Published var helperRequiresBackgroundApproval: Bool = false
    @Published var rawLinuxImageSelectionEnabled: Bool = false
    @Published private(set) var isDownloaderAccessBlocked: Bool = false
    @Published private(set) var isLanguageChangeEnabled: Bool = true
    @Published var debugCopiedDataLabel: String = String(
        format: String(localized: "Przekopiowane dane: %.1f GB"),
        0.0
    )

    private var downloaderBlockReasons: Set<String> = []
    private var languageChangesLockedForWorkflow = false
    private var hasActiveOperations = false
    private var cancellables: Set<AnyCancellable> = []
    
    func enableExternalDrives() {
        UserDefaults.standard.set(true, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        self.externalDrivesEnabled = true
    }

    func updateDebugCopiedData(bytes: Int64) {
        let gigabytes = max(0, Double(bytes)) / 1_073_741_824
        let label = String(
            format: String(localized: "Przekopiowane dane: %.1f GB"),
            gigabytes
        )

        if Thread.isMainThread {
            debugCopiedDataLabel = label
        } else {
            DispatchQueue.main.async {
                self.debugCopiedDataLabel = label
            }
        }
    }

    func setDownloaderAccessBlocked(_ blocked: Bool, reason: String) {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else { return }

        if blocked {
            downloaderBlockReasons.insert(normalizedReason)
        } else {
            downloaderBlockReasons.remove(normalizedReason)
        }

        let nextValue = !downloaderBlockReasons.isEmpty
        if Thread.isMainThread {
            isDownloaderAccessBlocked = nextValue
        } else {
            DispatchQueue.main.async {
                self.isDownloaderAccessBlocked = nextValue
            }
        }
    }

    func lockLanguageChanges(reason: String) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard !languageChangesLockedForWorkflow else { return }
            languageChangesLockedForWorkflow = true
            refreshLanguageChangeAvailability()
            AppLogging.info(
                "Zablokowano zmianę języka dla bieżącego przepływu [reason=\(reason)].",
                category: "AppLifecycle"
            )
        }
    }

    func resetLanguageChangesForWelcome() {
        performOnMain { [weak self] in
            guard let self else { return }
            languageChangesLockedForWorkflow = false
            refreshLanguageChangeAvailability()
        }
    }

    private func refreshLanguageChangeAvailability() {
        isLanguageChangeEnabled = !languageChangesLockedForWorkflow && !hasActiveOperations
    }

    private func performOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
    
    private init() {
        AppActiveOperationRegistry.shared.$activeOperationCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.hasActiveOperations = count > 0
                self?.refreshLanguageChangeAvailability()
            }
            .store(in: &cancellables)
    }
}
