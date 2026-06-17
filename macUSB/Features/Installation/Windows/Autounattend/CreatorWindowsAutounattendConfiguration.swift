import Foundation

enum CreatorWindowsAutounattendWindowsVersion {
    case windows11

    var supportsHardwareBypass: Bool {
        true
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
        return nil
    }
}

enum CreatorWindowsAutounattendExistingFileDecision: String {
    case useExisting
    case replaceWithMacUSB
    case stop
}

struct CreatorWindowsAutounattendMacLocale: Equatable {
    let languageTag: String
    let regionLocaleTag: String
    let languageIsAvailableInSource: Bool

    static func current(availableLanguageTags: Set<String>?) -> CreatorWindowsAutounattendMacLocale? {
        guard let languageTag = normalizedWindowsTag(Locale.preferredLanguages.first) else {
            return nil
        }

        let regionLocaleTag = normalizedWindowsTag(Locale.current.identifier) ?? languageTag
        let languageIsAvailableInSource = languageTagIsAvailable(languageTag, in: availableLanguageTags)
        return CreatorWindowsAutounattendMacLocale(
            languageTag: languageTag,
            regionLocaleTag: regionLocaleTag,
            languageIsAvailableInSource: languageIsAvailableInSource
        )
    }

    static func normalizedWindowsTag(_ value: String?) -> String? {
        guard let value else { return nil }
        let stripped = value
            .split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? value
        let normalized = stripped
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func languageTagIsAvailable(_ languageTag: String, in availableLanguageTags: Set<String>?) -> Bool {
        guard let availableLanguageTags else { return false }
        let normalized = languageTag.lowercased()
        if availableLanguageTags.contains(normalized) {
            return true
        }

        let languageCode = normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
        guard !languageCode.isEmpty else { return false }
        return availableLanguageTags.contains { availableTag in
            availableTag == languageCode || availableTag.hasPrefix("\(languageCode)-")
        }
    }
}

struct CreatorWindowsAutounattendConfiguration: Equatable {
    var skipHardwareRequirements: Bool = false
    var useMacLanguageAndRegion: Bool = false
    var macLocale: CreatorWindowsAutounattendMacLocale?
    var preventDeviceEncryption: Bool = false
    var disableDataCollection: Bool = false
    var skipWirelessSetup: Bool = false
    var skipMicrosoftAccountRequirement: Bool = false
    var createLocalAccount: Bool = false
    var localAccountName: String = ""
    var existingFileDecision: CreatorWindowsAutounattendExistingFileDecision?

    var trimmedLocalAccountName: String {
        localAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSelectedOption: Bool {
        skipHardwareRequirements
            || useMacLanguageAndRegion
            || preventDeviceEncryption
            || disableDataCollection
            || skipWirelessSetup
            || skipMicrosoftAccountRequirement
            || createLocalAccount
    }

    var shouldGenerateMacUSBFile: Bool {
        hasSelectedOption && existingFileDecision != .useExisting
    }

    var isLocalAccountNameValid: Bool {
        guard createLocalAccount else { return true }
        return Self.isValidLocalAccountName(trimmedLocalAccountName)
    }

    var canUseMacLanguageAndRegion: Bool {
        macLocale?.languageIsAvailableInSource == true
    }

    var canStartWorkflow: Bool {
        hasSelectedOption ? isLocalAccountNameValid : true
    }

    mutating func normalize(for version: CreatorWindowsAutounattendWindowsVersion?) {
        if version?.supportsHardwareBypass != true {
            skipHardwareRequirements = false
        }
        if !canUseMacLanguageAndRegion {
            useMacLanguageAndRegion = false
        }
        if createLocalAccount {
            skipMicrosoftAccountRequirement = true
        }
        if skipWirelessSetup {
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
            useMacLanguageAndRegion: useMacLanguageAndRegion,
            languageTag: useMacLanguageAndRegion ? macLocale?.languageTag : nil,
            regionLocaleTag: useMacLanguageAndRegion ? macLocale?.regionLocaleTag : nil,
            preventDeviceEncryption: preventDeviceEncryption,
            disableDataCollection: disableDataCollection,
            skipWirelessSetup: skipWirelessSetup,
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
        guard CreatorWindowsAutounattendWindowsVersion.detected(from: systemName) != nil else {
            configurations.removeValue(forKey: key(for: sourceURL))
            return CreatorWindowsAutounattendConfiguration()
        }

        var configuration = configurations[key(for: sourceURL)] ?? CreatorWindowsAutounattendConfiguration()
        configuration.normalize(for: CreatorWindowsAutounattendWindowsVersion.detected(from: systemName))
        return configuration
    }

    func store(_ configuration: CreatorWindowsAutounattendConfiguration, for sourceURL: URL, systemName: String) {
        guard CreatorWindowsAutounattendWindowsVersion.detected(from: systemName) != nil else {
            configurations.removeValue(forKey: key(for: sourceURL))
            return
        }

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
