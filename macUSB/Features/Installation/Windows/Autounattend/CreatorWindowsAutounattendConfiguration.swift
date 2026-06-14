import Foundation

enum CreatorWindowsAutounattendWindowsVersion {
    case windows10
    case windows11

    var supportsHardwareBypass: Bool {
        self == .windows11
    }

    static func detected(from systemName: String) -> CreatorWindowsAutounattendWindowsVersion? {
        let normalized = systemName.lowercased()
        guard normalized.contains("windows"),
              !normalized.contains("server") else {
            return nil
        }
        if normalized.contains("windows 11") {
            return .windows11
        }
        if normalized.contains("windows 10") {
            return .windows10
        }
        return nil
    }
}

enum CreatorWindowsAutounattendExistingFileDecision: String {
    case useExisting
    case replaceWithMacUSB
    case stop
}

struct CreatorWindowsAutounattendConfiguration: Equatable {
    var skipHardwareRequirements: Bool = false
    var preventDeviceEncryption: Bool = false
    var skipLicenseScreen: Bool = false
    var skipMicrosoftAccountRequirement: Bool = false
    var createLocalAccount: Bool = false
    var localAccountName: String = ""
    var existingFileDecision: CreatorWindowsAutounattendExistingFileDecision?

    var trimmedLocalAccountName: String {
        localAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSelectedOption: Bool {
        skipHardwareRequirements || preventDeviceEncryption || skipLicenseScreen || skipMicrosoftAccountRequirement || createLocalAccount
    }

    var shouldGenerateMacUSBFile: Bool {
        hasSelectedOption && existingFileDecision != .useExisting
    }

    var isLocalAccountNameValid: Bool {
        guard createLocalAccount else { return true }
        return Self.isValidLocalAccountName(trimmedLocalAccountName)
    }

    var canStartWorkflow: Bool {
        hasSelectedOption ? isLocalAccountNameValid : true
    }

    mutating func normalize(for version: CreatorWindowsAutounattendWindowsVersion?) {
        if version?.supportsHardwareBypass != true {
            skipHardwareRequirements = false
        }
        if createLocalAccount {
            skipMicrosoftAccountRequirement = true
        }
        if !skipMicrosoftAccountRequirement {
            createLocalAccount = false
        }
        if !createLocalAccount {
            localAccountName = ""
        }
    }

    func helperPayload() -> WindowsAutounattendConfigurationPayload? {
        guard shouldGenerateMacUSBFile else { return nil }
        return WindowsAutounattendConfigurationPayload(
            skipHardwareRequirements: skipHardwareRequirements,
            preventDeviceEncryption: preventDeviceEncryption,
            skipLicenseScreen: skipLicenseScreen,
            skipMicrosoftAccountRequirement: skipMicrosoftAccountRequirement,
            createLocalAccount: createLocalAccount,
            localAccountName: createLocalAccount ? trimmedLocalAccountName : nil
        )
    }

    static func isValidLocalAccountName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }
}

@MainActor
final class CreatorWindowsAutounattendSessionStore {
    static let shared = CreatorWindowsAutounattendSessionStore()

    private var configurations: [String: CreatorWindowsAutounattendConfiguration] = [:]

    private init() {}

    func configuration(for sourceURL: URL, systemName: String) -> CreatorWindowsAutounattendConfiguration {
        var configuration = configurations[key(for: sourceURL)] ?? CreatorWindowsAutounattendConfiguration()
        configuration.normalize(for: CreatorWindowsAutounattendWindowsVersion.detected(from: systemName))
        return configuration
    }

    func store(_ configuration: CreatorWindowsAutounattendConfiguration, for sourceURL: URL, systemName: String) {
        var normalized = configuration
        normalized.normalize(for: CreatorWindowsAutounattendWindowsVersion.detected(from: systemName))
        normalized.existingFileDecision = nil
        configurations[key(for: sourceURL)] = normalized
    }

    private func key(for sourceURL: URL) -> String {
        var parts = [sourceURL.standardizedFileURL.path]
        if let values = try? sourceURL.resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let identifier = values.fileResourceIdentifier {
            parts.append(String(describing: identifier))
        }
        return parts.joined(separator: "::")
    }
}
