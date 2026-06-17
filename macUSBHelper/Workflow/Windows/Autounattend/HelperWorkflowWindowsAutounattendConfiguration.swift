import Foundation

extension WindowsAutounattendConfigurationPayload {
    var shouldGenerateFile: Bool {
        skipHardwareRequirements
            || useMacLanguageAndRegion
            || preventDeviceEncryption
            || disableDataCollection
            || skipWirelessSetup
            || skipMicrosoftAccountRequirement
            || createLocalAccount
    }

    var requiresWindowsPE: Bool {
        skipHardwareRequirements
    }

    var normalizedLocalAccountName: String? {
        localAccountName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLanguageTag: String? {
        normalizedWindowsLocaleTag(languageTag)
    }

    var normalizedRegionLocaleTag: String? {
        normalizedWindowsLocaleTag(regionLocaleTag)
    }

    private func normalizedWindowsLocaleTag(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

}

extension HelperWorkflowExecutor {
    var windowsAutounattendProcessorArchitecture: String {
        request.systemName.lowercased().contains("arm") ? "arm64" : "amd64"
    }
}
