import Foundation

extension UniversalInstallationView {
    func windowsTargetVolumeLabel() -> String {
        let normalized = systemName.lowercased()

        if normalized.contains("server 2025") {
            return "SRV25-MU"
        }
        if normalized.contains("server 2022") {
            return "SRV22-MU"
        }
        if normalized.contains("server 2019") {
            return "SRV19-MU"
        }
        if normalized.contains("server 2016") {
            return "SRV16-MU"
        }
        if normalized.contains("server 2012") {
            return "SRV12-MU"
        }

        if normalized.contains("windows 11") {
            return "WIN11-MU"
        }
        if normalized.contains("windows 10") {
            return "WIN10-MU"
        }
        if normalized.contains("windows 8.1") {
            return "WIN81-MU"
        }
        if normalized.contains("windows 8") {
            return "WIN8-MU"
        }

        return "WIN10-MU"
    }
}
