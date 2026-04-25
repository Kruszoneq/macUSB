import Foundation

extension AnalysisLogic {
    var linuxInstallationFlowContext: LinuxInstallationFlowContext? {
        guard isLinuxDetected, let linuxSourceURL else {
            return nil
        }

        return LinuxInstallationFlowContext(
            sourceImageURL: linuxSourceURL,
            mountedImagePath: mountedDMGPath
        )
    }
}
