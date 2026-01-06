import Foundation
import Combine

final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var skipAnalysisEnabled: Bool = false
    @Published var externalDrivesEnabled: Bool = UserDefaults.standard.bool(forKey: "AllowExternalDrives")
    
    func enableExternalDrives() {
        UserDefaults.standard.set(true, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        self.externalDrivesEnabled = true
    }
    
    private init() {}
}
