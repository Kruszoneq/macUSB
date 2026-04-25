import Foundation
import AppKit
import SwiftUI

private enum LinuxDistroIconCatalog {
    static let names: [String] = [
        "alpine", "antix", "arch", "arco", "artix", "bluestar", "bodhi", "bunsenlabs",
        "clear", "debian", "deepin", "elementary", "endeavour", "endless", "feren",
        "gentoo", "kali", "kaos", "knoppix", "kubuntu", "linux", "lite", "lubuntu",
        "mageia", "manjaro", "mint", "mx", "neon", "netrunner", "nixos", "openmandriva",
        "parrot", "pclinuxos", "peppermint", "pop", "qubes", "raspios", "rebornos",
        "redhat", "rosa", "septor", "slackware", "solus", "suse", "tails", "tinycore",
        "ubuntu", "ubuntu_cinnamon", "ubuntu_dde", "ubuntu_mate", "void", "xubuntu", "zorin"
    ]

    static let namesSet = Set(names)

    static let aliases: [String: [String]] = [
        "alpine linux": ["alpine"],
        "anti x": ["antix"],
        "antix": ["antix"],
        "arch linux": ["arch"],
        "arcolinux": ["arco"],
        "artix linux": ["artix"],
        "bluestar linux": ["bluestar"],
        "bodhi linux": ["bodhi"],
        "bunsenlabs linux": ["bunsenlabs"],
        "clear linux": ["clear"],
        "debian gnu linux": ["debian"],
        "deepin linux": ["deepin"],
        "elementary os": ["elementary"],
        "endeavouros": ["endeavour"],
        "endless os": ["endless"],
        "fedora": ["redhat"],
        "feren os": ["feren"],
        "gentoo linux": ["gentoo"],
        "kali linux": ["kali"],
        "kaos linux": ["kaos"],
        "knoppix linux": ["knoppix"],
        "kde neon": ["neon"],
        "kubuntu": ["kubuntu"],
        "linux lite": ["lite"],
        "lubuntu": ["lubuntu"],
        "mageia linux": ["mageia"],
        "linux mint": ["mint"],
        "mx linux": ["mx"],
        "nitrux": ["neon"],
        "nixos": ["nixos"],
        "open mandriva": ["openmandriva"],
        "openmandriva lx": ["openmandriva"],
        "openmamba": ["openmandriva"],
        "opensuse": ["suse"],
        "opensuse leap": ["suse"],
        "opensuse tumbleweed": ["suse"],
        "parrot os": ["parrot"],
        "pclinuxos": ["pclinuxos"],
        "peppermint os": ["peppermint"],
        "pop os": ["pop"],
        "popos": ["pop"],
        "pop os linux": ["pop"],
        "qubes os": ["qubes"],
        "raspberry pi os": ["raspios"],
        "raspian": ["raspios"],
        "red hat": ["redhat"],
        "red hat enterprise linux": ["redhat"],
        "rhel": ["redhat"],
        "rosa linux": ["rosa"],
        "septor linux": ["septor"],
        "slackware linux": ["slackware"],
        "solus os": ["solus"],
        "suse linux": ["suse"],
        "tails linux": ["tails"],
        "tiny core linux": ["tinycore"],
        "almalinux": ["redhat"],
        "ubuntu mate": ["ubuntu_mate", "ubuntu"],
        "ubuntu cinnamon": ["ubuntu_cinnamon", "ubuntu"],
        "ubuntu dde": ["ubuntu_dde", "ubuntu"],
        "ubuntu unity": ["ubuntu"],
        "void linux": ["void"],
        "xubuntu": ["xubuntu"],
        "zorin os": ["zorin"]
    ]

    static let noiseWords: Set<String> = [
        "linux", "gnu", "os", "edition", "desktop", "live", "installer", "install", "lts", "release"
    ]
}

extension AnalysisLogic {
    func forceLinuxManualSelection() {
        guard let sourceURL = self.selectedFileUrl else {
            self.logError("Nie można wymusić rozpoznania Linux: brak wybranego pliku.")
            return
        }

        self.log("Ręcznie wybrano tryb Linux (pominięcie analizy pliku).")

        withAnimation {
            self.isAnalyzing = false
            self.userSkippedAnalysis = true
            self.resetLinuxDetectionState()

            self.isLinuxDetected = true
            self.isLinuxDistributionRecognized = false
            self.linuxDisplayName = "Linux"
            self.linuxSourceURL = sourceURL

            self.recognizedVersion = "Linux"
            self.sourceAppURL = nil
            self.detectedSystemIcon = loadLinuxDetectedSystemIcon(for: nil)

            self.isSystemDetected = true
            self.showUnsupportedMessage = false
            self.showUSBSection = false

            self.needsCodesign = true
            self.isLegacyDetected = false
            self.isRestoreLegacy = false
            self.isCatalina = false
            self.isSierra = false
            self.isMavericks = false
            self.isUnsupportedSierra = false
            self.isPPC = false
            self.legacyArchInfo = nil
            self.selectedDrive = nil
            self.capacityCheckFinished = false
        }

        if let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize {
            let fileSizeBytes = Int64(fileSize)
            let requiredGB = linuxRequiredUSBCapacityGB(fromFileSizeBytes: fileSizeBytes)
            self.requiredUSBCapacityGB = requiredGB
            self.log("Linux manual source size: \(fileSizeBytes) bytes")
            self.log("Linux manual required USB threshold: \(requiredGB) GB")
        } else {
            self.requiredUSBCapacityGB = nil
            self.logError("Nie udało się odczytać rozmiaru pliku dla ręcznego trybu Linux. Minimalna pojemność USB pozostaje nierozstrzygnięta (-- GB).")
        }

        self.log("Ustawiono ręczne rozpoznanie Linux: recognizedVersion=\(self.recognizedVersion), source=\(sourceURL.path)")
    }

    private func linuxRequiredUSBCapacityGB(fromFileSizeBytes fileSizeBytes: Int64) -> Int {
        if fileSizeBytes > 14_000_000_000 {
            return 32
        }
        if fileSizeBytes > 6_000_000_000 {
            return 16
        }
        return 8
    }

    private func resolveLinuxSourceFileSizeBytes(for sourceURL: URL) -> (bytes: Int64, source: String)? {
        if let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize {
            return (Int64(fileSize), "fileSizeKey")
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let size = attributes[.size] as? NSNumber {
            return (size.int64Value, "attributesOfItem")
        }

        return nil
    }

    private func loadLinuxDetectedSystemIcon(for distro: String?) -> NSImage? {
        if let distro, let distroIcon = loadLinuxDistroIcon(for: distro) {
            self.log("Załadowano ikonę Linux distro: \(distro)")
            return distroIcon
        }

        let nestedURL = Bundle.main.url(forResource: "linux", withExtension: "icns", subdirectory: "Icons/Linux")
        let rootURL = Bundle.main.url(forResource: "linux", withExtension: "icns")
        guard let url = nestedURL ?? rootURL, let icon = NSImage(contentsOf: url) else {
            self.log("Nie znaleziono fallback ikony linux.icns - zostanie użyty SF Symbol.", category: "FileAnalysis")
            return nil
        }
        icon.isTemplate = false
        self.log("Załadowano fallback ikonę linux.icns.", category: "FileAnalysis")
        return icon
    }

    private func loadLinuxDistroIcon(for distro: String) -> NSImage? {
        let candidates = linuxDistroIconResourceCandidates(for: distro)

        for candidate in candidates {
            if let nestedURL = Bundle.main.url(forResource: candidate, withExtension: "png", subdirectory: "Icons/Linux/Distros"),
               let icon = NSImage(contentsOf: nestedURL) {
                icon.isTemplate = false
                return icon
            }

            if let bundledDistrosURL = Bundle.main.url(forResource: candidate, withExtension: "png", subdirectory: "Distros"),
               let icon = NSImage(contentsOf: bundledDistrosURL) {
                icon.isTemplate = false
                return icon
            }

            if let rootURL = Bundle.main.url(forResource: candidate, withExtension: "png"),
               let icon = NSImage(contentsOf: rootURL) {
                icon.isTemplate = false
                return icon
            }
        }

        self.log("Brak dedykowanej ikony distro dla: \(distro). Kandydaci: \(candidates.joined(separator: ", "))", category: "FileAnalysis")
        return nil
    }

    private func linuxDistroIconResourceCandidates(for distro: String) -> [String] {
        let normalized = normalizeLinuxDistroLookupKey(distro)
        guard !normalized.isEmpty else { return [] }

        var candidates: [String] = []
        func appendCandidate(_ candidate: String) {
            guard LinuxDistroIconCatalog.namesSet.contains(candidate), !candidates.contains(candidate) else { return }
            candidates.append(candidate)
        }

        if let aliasCandidates = LinuxDistroIconCatalog.aliases[normalized] {
            aliasCandidates.forEach(appendCandidate)
        }

        let words = normalized.split(separator: " ").map(String.init)
        let compact = words.joined()
        let underscored = words.joined(separator: "_")
        appendCandidate(underscored)
        appendCandidate(compact)
        words.forEach(appendCandidate)

        let strippedWords = words.filter { !LinuxDistroIconCatalog.noiseWords.contains($0) }
        if !strippedWords.isEmpty {
            let strippedPhrase = strippedWords.joined(separator: " ")
            if let aliasCandidates = LinuxDistroIconCatalog.aliases[strippedPhrase] {
                aliasCandidates.forEach(appendCandidate)
            }

            appendCandidate(strippedWords.joined(separator: "_"))
            appendCandidate(strippedWords.joined())
            strippedWords.forEach(appendCandidate)
        }

        for iconName in LinuxDistroIconCatalog.names where iconName.count >= 4 {
            let compactIconName = iconName.replacingOccurrences(of: "_", with: "")
            if compact.contains(compactIconName) {
                appendCandidate(iconName)
            }
        }

        return candidates
    }

    private func normalizeLinuxDistroLookupKey(_ rawValue: String) -> String {
        let lowered = rawValue.lowercased()
        let normalized = lowered.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func resetLinuxDetectionState() {
        self.isLinuxDetected = false
        self.isLinuxDistributionRecognized = false
        self.linuxDistro = nil
        self.linuxVersion = nil
        self.linuxEdition = nil
        self.linuxArchitecture = nil
        self.isLinuxARM = false
        self.linuxDisplayName = nil
        self.linuxSourceURL = nil
    }

    func applyLinuxDetectionResult(_ result: LinuxDetectionResult, sourceURL: URL, mountedImagePath: String?) {
        self.isLinuxDetected = result.isLinux
        self.isLinuxDistributionRecognized = result.isDistributionRecognized
        self.linuxDistro = result.distro
        self.linuxVersion = result.version
        self.linuxEdition = result.edition
        self.linuxArchitecture = result.archRaw
        self.isLinuxARM = result.isARM
        self.linuxDisplayName = result.displayName
        self.linuxSourceURL = sourceURL

        self.recognizedVersion = result.displayName
        self.sourceAppURL = nil
        self.detectedSystemIcon = loadLinuxDetectedSystemIcon(for: result.distro)
        self.mountedDMGPath = mountedImagePath

        self.isSystemDetected = true
        self.showUnsupportedMessage = false
        self.showUSBSection = false

        self.needsCodesign = true
        self.isLegacyDetected = false
        self.isRestoreLegacy = false
        self.isCatalina = false
        self.isSierra = false
        self.isMavericks = false
        self.isUnsupportedSierra = false
        self.isPPC = false
        self.legacyArchInfo = nil
        self.userSkippedAnalysis = false
        if let fileSizeResolution = resolveLinuxSourceFileSizeBytes(for: sourceURL) {
            let requiredGB = linuxRequiredUSBCapacityGB(fromFileSizeBytes: fileSizeResolution.bytes)
            self.requiredUSBCapacityGB = requiredGB
            self.log("Linux source size: \(fileSizeResolution.bytes) bytes (source=\(fileSizeResolution.source))")
            self.log("Linux required USB threshold: \(requiredGB) GB")
        } else {
            self.requiredUSBCapacityGB = nil
            self.logError("Nie udało się odczytać rozmiaru pliku Linux. Minimalna pojemność USB pozostaje nierozstrzygnięta (-- GB).")
        }

        self.log("Rozpoznano obraz Linux: \(result.displayName)")
        self.log("Linux source file: \(sourceURL.path)")
        self.log("Linux details: distro=\(result.distro ?? "?") version=\(result.version ?? "?") edition=\(result.edition ?? "?") arch=\(result.archRaw ?? "?") arm=\(result.isARM ? "TAK" : "NIE")")
        self.log("Linux evidence: \(result.evidence.joined(separator: ", "))")
        AppLogging.separator()
    }
}
