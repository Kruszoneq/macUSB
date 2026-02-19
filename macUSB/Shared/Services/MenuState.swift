import Foundation
import Combine

final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var skipAnalysisEnabled: Bool = false
    @Published var externalDrivesEnabled: Bool = UserDefaults.standard.bool(forKey: "AllowExternalDrives")
    @Published var notificationsEnabled: Bool = false
    @Published var debugCopiedDataLabel: String = String(
        format: String(localized: "Przekopiowane dane: %.1f GB"),
        0.0
    )
    
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
    
    private init() {}
}
