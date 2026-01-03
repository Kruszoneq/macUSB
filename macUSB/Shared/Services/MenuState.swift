import Foundation
import Combine

final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var skipAnalysisEnabled: Bool = false
    private init() {}
}
