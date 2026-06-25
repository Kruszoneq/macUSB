import Foundation

enum CreatorWindowsAutounattendWindowsVersion {
    case windows10
    case windows11

    var supportsHardwareBypass: Bool {
        switch self {
        case .windows10:
            return false
        case .windows11:
            return true
        }
    }

    static func detected(
        from systemName: String,
        architecture: WindowsArchitecture? = nil
    ) -> CreatorWindowsAutounattendWindowsVersion? {
        let normalized = systemName.lowercased()
        guard normalized.contains("windows"),
              !normalized.contains("server") else {
            return nil
        }
        if normalized.contains("windows 10") {
            guard architecture == .x86_64 else { return nil }
            return .windows10
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
    static let localAccountNameMaximumLength = 20
    static let localAccountDisplayNameMaximumLength = 256

    var skipHardwareRequirements: Bool = false
    var useMacLanguageAndRegion: Bool = false
    var macLocale: CreatorWindowsAutounattendMacLocale?
    var preventDeviceEncryption: Bool = false
    var disableDataCollection: Bool = false
    var skipWirelessSetup: Bool = false
    var skipMicrosoftAccountRequirement: Bool = false
    var createLocalAccount: Bool = false
    var localAccountDisplayName: String = ""
    var existingFileDecision: CreatorWindowsAutounattendExistingFileDecision?

    var trimmedLocalAccountDisplayName: String {
        localAccountDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var generatedLocalAccountName: String? {
        Self.generatedLocalAccountName(from: trimmedLocalAccountDisplayName)
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

    var isLocalAccountDisplayNameValid: Bool {
        guard createLocalAccount else { return true }
        return Self.isValidLocalAccountDisplayName(trimmedLocalAccountDisplayName)
            && generatedLocalAccountName != nil
    }

    var canUseMacLanguageAndRegion: Bool {
        macLocale?.languageIsAvailableInSource == true
    }

    var canStartWorkflow: Bool {
        hasSelectedOption ? isLocalAccountDisplayNameValid : true
    }

    var canDismissOptionsSheet: Bool {
        isLocalAccountDisplayNameValid
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
            localAccountDisplayName = ""
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
            localAccountName: createLocalAccount ? generatedLocalAccountName : nil,
            localAccountDisplayName: createLocalAccount ? trimmedLocalAccountDisplayName : nil
        )
    }

    static func isValidLocalAccountDisplayName(_ displayName: String) -> Bool {
        !displayName.isEmpty
            && displayName.count <= localAccountDisplayNameMaximumLength
            && !containsInvalidLocalAccountDisplayNameCharacter(displayName)
            && displayName.uppercased() != "NONE"
    }

    static func isValidLocalAccountName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= localAccountNameMaximumLength else { return false }
        guard name.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else { return false }
        return name.uppercased() != "NONE"
    }

    static func containsInvalidLocalAccountDisplayNameCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { !isAllowedLocalAccountDisplayNameScalar($0) }
    }

    private static func isAllowedLocalAccountDisplayNameScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.letters.contains(scalar)
            || CharacterSet.decimalDigits.contains(scalar)
            || scalar == " "
    }

    static func generatedLocalAccountName(from displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidLocalAccountDisplayName(trimmed) else { return nil }

        let folded = asciiTransliteratedDisplayName(trimmed)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let asciiAlphanumerics = folded.unicodeScalars.compactMap { scalar -> Character? in
            switch scalar.value {
            case 48...57, 65...90, 97...122:
                return Character(scalar)
            default:
                return nil
            }
        }
        let candidate = String(asciiAlphanumerics.prefix(localAccountNameMaximumLength))
        let normalizedCandidate = candidate.uppercased()
        if isValidLocalAccountName(candidate), normalizedCandidate != "NONE" {
            return candidate
        }

        let fallback = fallbackLocalAccountName(for: trimmed)
        return isValidLocalAccountName(fallback) ? fallback : nil
    }

    private static func fallbackLocalAccountName(for displayName: String) -> String {
        let bytes = Array(displayName.utf8)
        let hash = bytes.reduce(UInt32(2_166_136_261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16_777_619
        }
        return "User\(String(hash, radix: 16, uppercase: true))"
    }

    private static func asciiTransliteratedDisplayName(_ displayName: String) -> String {
        let replacements = [
            "Ł": "L", "ł": "l",
            "Æ": "AE", "æ": "ae",
            "Œ": "OE", "œ": "oe",
            "Ø": "O", "ø": "o",
            "Ð": "D", "ð": "d",
            "Đ": "D", "đ": "d",
            "Þ": "Th", "þ": "th",
            "ß": "ss"
        ]
        return replacements.reduce(displayName) { result, replacement in
            result.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }
}

@MainActor
final class CreatorWindowsAutounattendSessionStore {
    static let shared = CreatorWindowsAutounattendSessionStore()

    private var configurations: [String: CreatorWindowsAutounattendConfiguration] = [:]

    private init() {}

    func configuration(
        for sourceURL: URL,
        systemName: String,
        architecture: WindowsArchitecture?
    ) -> CreatorWindowsAutounattendConfiguration {
        guard CreatorWindowsAutounattendWindowsVersion.detected(
            from: systemName,
            architecture: architecture
        ) != nil else {
            configurations.removeValue(forKey: key(for: sourceURL))
            return CreatorWindowsAutounattendConfiguration()
        }

        var configuration = configurations[key(for: sourceURL)] ?? CreatorWindowsAutounattendConfiguration()
        configuration.normalize(for: CreatorWindowsAutounattendWindowsVersion.detected(
            from: systemName,
            architecture: architecture
        ))
        return configuration
    }

    func store(
        _ configuration: CreatorWindowsAutounattendConfiguration,
        for sourceURL: URL,
        systemName: String,
        architecture: WindowsArchitecture?
    ) {
        guard CreatorWindowsAutounattendWindowsVersion.detected(
            from: systemName,
            architecture: architecture
        ) != nil else {
            configurations.removeValue(forKey: key(for: sourceURL))
            return
        }

        var normalized = configuration
        normalized.normalize(for: CreatorWindowsAutounattendWindowsVersion.detected(
            from: systemName,
            architecture: architecture
        ))
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
