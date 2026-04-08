import Foundation
import Combine

final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var skipAnalysisEnabled: Bool = false
    @Published var externalDrivesEnabled: Bool = UserDefaults.standard.bool(forKey: "AllowExternalDrives")
    @Published var notificationsEnabled: Bool = false
    @Published var hasFullDiskAccess: Bool = true
    @Published var helperRequiresBackgroundApproval: Bool = false
    @Published private(set) var isDownloaderAccessBlocked: Bool = false
    @Published var debugCopiedDataLabel: String = String(
        format: String(localized: "Przekopiowane dane: %.1f GB"),
        0.0
    )

    private var downloaderBlockReasons: Set<String> = []
    
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
    
    private init() {}
}
