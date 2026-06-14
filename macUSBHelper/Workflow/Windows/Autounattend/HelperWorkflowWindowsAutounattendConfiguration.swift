import Foundation

extension WindowsAutounattendConfigurationPayload {
    var shouldGenerateFile: Bool {
        skipHardwareRequirements || skipLicenseScreen || createLocalAccount
    }

    var normalizedLocalAccountName: String? {
        localAccountName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension HelperWorkflowExecutor {
    var windowsAutounattendProcessorArchitecture: String {
        request.systemName.lowercased().contains("arm") ? "arm64" : "amd64"
    }
}
