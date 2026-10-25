import Foundation

extension UniversalInstallationView {
    func windowsMacUSBootErrorMessage(for result: HelperWorkflowResultPayload) -> String? {
        guard isWindowsWorkflow,
              !result.success,
              result.failedStage == CreationProgressWindowsMapping.installMacUSBootStageKey else {
            return nil
        }
        return String(localized: "creator.windows.error.macusboot", table: "Creator")
    }
}
