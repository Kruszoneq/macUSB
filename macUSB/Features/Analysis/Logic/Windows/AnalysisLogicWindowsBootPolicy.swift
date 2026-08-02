import Foundation

extension AnalysisLogic {
    func qualifyWindowsBootCapabilities(
        _ capabilities: WindowsBootCapabilities,
        for family: WindowsFamily,
        architecture: WindowsArchitecture
    ) -> WindowsBootCapabilities {
        var eligibleModes: Set<WindowsBootMode>
        switch family {
        case .xp, .server2003:
            eligibleModes = []
        case .vista, .seven, .server2008R2:
            eligibleModes = capabilities.hasBIOS ? [.bios] : []
        case .eight, .eightOne, .ten,
             .server2012, .server2012R2, .server2016, .server2019, .server2022:
            eligibleModes = capabilities.detectedModes
        case .eleven, .server2025:
            eligibleModes = capabilities.hasUEFI ? [.uefi] : []
        }

        if architecture == .arm {
            eligibleModes = eligibleModes.intersection([.uefi])
        }

        return capabilities.withEligibleModes(eligibleModes)
    }
}
