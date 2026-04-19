import Foundation

extension AnalysisLogic {
    func buildLinuxDisplayName(distro: String?, version: String?, isARM: Bool) -> String {
        let base: String
        if let distro, !distro.isEmpty {
            if let version, !version.isEmpty {
                base = "Linux - \(distro) \(version)"
            } else {
                base = "Linux - \(distro)"
            }
        } else {
            base = String(localized: "Linux - nierozpoznana dystrybucja")
        }

        guard isARM else { return base }
        return "\(base) (ARM)"
    }
}
