import Foundation

extension AnalysisLogic {
    func detectWindowsToolchainPresence() -> WindowsToolchainPresence {
        WindowsToolchainProbeService.shared.detectPresence()
    }
}
