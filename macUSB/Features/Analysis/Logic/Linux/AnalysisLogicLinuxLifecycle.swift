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
        cancelActiveImageAnalysisRun(reason: "Ręczne wymuszenie trybu Linux")
        guard let sourceURL = self.selectedFileUrl else {
            self.logError("Nie można wymusić rozpoznania Linux: brak wybranego pliku.")
            return
        }
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard sourceExtension == "iso" else {
            self.logError("Nie można wymusić rozpoznania Linux dla .\(sourceExtension). Opcja „Pomiń analizowanie pliku -> Linux” jest dostępna tylko dla plików .iso.")
            return
        }

        InstallerSourceImageUnmountRegistry.shared.registerSourceImage(
            path: sourceURL.path,
            family: .linux,
            mountHint: mountedDMGPath,
            reason: "linux_manual_selection"
        )

        self.log("Ręcznie wybrano tryb Linux (pominięcie analizy pliku).")

        withAnimation {
            self.isAnalyzing = false
            self.userSkippedAnalysis = true
            self.resetLinuxDetectionState()
            self.resetWindowsDetectionState()

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

        let capacityResolution = resolveRequiredUSBCapacityForImageSource(sourceURL)
        self.requiredUSBCapacityGB = capacityResolution.requiredCapacityGB
        if let fileSizeBytes = capacityResolution.sourceFileSizeBytes,
           let fileSizeSource = capacityResolution.sourceFileSizeSource {
            self.log("Linux manual source size: \(fileSizeBytes) bytes (source=\(fileSizeSource))")
        } else if capacityResolution.usedFallback {
            self.log("Linux manual source size unavailable. Applying fallback USB threshold: \(capacityResolution.requiredCapacityGB) GB")
        }
        self.log("Linux manual required USB threshold: \(capacityResolution.requiredCapacityGB) GB")

        self.log("Ustawiono ręczne rozpoznanie Linux: recognizedVersion=\(self.recognizedVersion), source=\(sourceURL.path)")
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
        cleanupLinuxAttachSession(reason: "reset_linux_detection_state")
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
        InstallerSourceImageUnmountRegistry.shared.registerSourceImage(
            path: sourceURL.path,
            family: .linux,
            mountHint: mountedImagePath,
            reason: "linux_detection_result"
        )

        self.resetWindowsDetectionState()
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
        let capacityResolution = resolveRequiredUSBCapacityForImageSource(sourceURL)
        self.requiredUSBCapacityGB = capacityResolution.requiredCapacityGB
        if let fileSizeBytes = capacityResolution.sourceFileSizeBytes,
           let fileSizeSource = capacityResolution.sourceFileSizeSource {
            self.log("Linux source size: \(fileSizeBytes) bytes (source=\(fileSizeSource))")
        } else if capacityResolution.usedFallback {
            self.log("Linux source size unavailable. Applying fallback USB threshold: \(capacityResolution.requiredCapacityGB) GB")
        }
        self.log("Linux required USB threshold: \(capacityResolution.requiredCapacityGB) GB")

        self.log("Rozpoznano obraz Linux: \(result.displayName)")
        self.log("Linux source file: \(sourceURL.path)")
        self.log("Linux details: distro=\(result.distro ?? "?") version=\(result.version ?? "?") edition=\(result.edition ?? "?") arch=\(result.archRaw ?? "?") arm=\(result.isARM ? "TAK" : "NIE")")
        self.log("Linux classification: rule=\(result.classificationRule) matched_signal=\(result.matchedSignal ?? "none") version_source=\(result.versionSource ?? "none")")
        self.log("Linux gate_signals: \(result.gateSignals.joined(separator: ", "))")
        self.log("Linux evidence: \(result.evidence.joined(separator: ", "))")
        cleanupLinuxAttachSession(reason: "linux_detection_completed_success")
        self.mountedDMGPath = nil
        AppLogging.separator()
    }
}

struct LinuxImageAttachSession {
    let imagePath: String
    let devEntries: [String]
    let mountPoints: [String]
    let entityCount: Int
}

extension AnalysisLogic {
    func captureLinuxAttachSessionIfNeeded(sourceURL: URL, reason: String) {
        let sourcePath = normalizedLinuxImagePath(sourceURL.path)
        if let currentSession = linuxImageAttachSession, currentSession.imagePath == sourcePath {
            return
        }
        if linuxImageAttachSession != nil {
            cleanupLinuxAttachSession(reason: "replace_session_before_capture")
        }

        guard let session = linuxAttachSessionForImagePath(sourcePath) else {
            linuxImageAttachSession = nil
            self.log("Linux mount session: brak encji dla obrazu \(sourceURL.lastPathComponent) [reason=\(reason)]")
            return
        }

        linuxImageAttachSession = session
        logLinuxAttachSessionSnapshot(session, reason: reason)
    }

    func cleanupLinuxAttachSession(reason: String) {
        guard let session = linuxImageAttachSession else { return }

        logLinuxAttachSessionSnapshot(session, reason: "\(reason):cleanup_start")

        let devDetachCandidates = session.devEntries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs > rhs }
                return lhs.count > rhs.count
            }

        for devEntry in devDetachCandidates {
            let result = detachLinuxImageEntity(identifier: devEntry)
            if result.success {
                self.log("Linux cleanup detach_ok identifier=\(devEntry) stage=dev-entry")
            } else {
                self.logError("Linux cleanup detach_fail identifier=\(devEntry) stage=dev-entry details=\(result.details ?? "unknown")")
            }
        }

        for mountPoint in session.mountPoints {
            let result = detachLinuxImageEntity(identifier: mountPoint)
            if result.success {
                self.log("Linux cleanup detach_ok identifier=\(mountPoint) stage=mount-point")
            } else {
                self.logError("Linux cleanup detach_fail identifier=\(mountPoint) stage=mount-point details=\(result.details ?? "unknown")")
            }
        }

        let residualSession = linuxAttachSessionForImagePath(session.imagePath)
        let residualEntitiesCount = residualSession?.entityCount ?? 0
        let allDetached = residualEntitiesCount == 0
        self.log("Linux cleanup summary reason=\(reason) all_detached=\(allDetached ? "TAK" : "NIE") residual_entities_count=\(residualEntitiesCount)")

        linuxImageAttachSession = nil
    }

    private func logLinuxAttachSessionSnapshot(_ session: LinuxImageAttachSession, reason: String) {
        self.log(
            "Linux mount session snapshot reason=\(reason) entities_count=\(session.entityCount) dev_entries=[\(session.devEntries.joined(separator: ", "))] mount_points=[\(session.mountPoints.joined(separator: ", "))]"
        )
    }

    private func detachLinuxImageEntity(identifier: String) -> (success: Bool, details: String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["detach", identifier, "-force"]
        let errorPipe = Pipe()
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (false, "run_error=\(error.localizedDescription)")
        }

        if task.terminationStatus == 0 {
            return (true, nil)
        }

        let stderrText = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stderrText.isEmpty {
            return (false, "termination_status=\(task.terminationStatus)")
        }
        return (false, "termination_status=\(task.terminationStatus) stderr=\(stderrText)")
    }

    private func linuxAttachSessionForImagePath(_ normalizedImagePath: String) -> LinuxImageAttachSession? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["info", "-plist"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            self.logError("Linux mount session: nie udało się uruchomić hdiutil info: \(error.localizedDescription)")
            return nil
        }
        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0 else {
            let stderrText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                self.logError("Linux mount session: hdiutil info zakończył się błędem (kod \(task.terminationStatus)).")
            } else {
                self.logError("Linux mount session: hdiutil info zakończył się błędem: \(stderrText)")
            }
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: outputData, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return nil
        }

        var devEntries: Set<String> = []
        var mountPoints: Set<String> = []
        var entityCount = 0

        for image in images {
            guard let imagePath = image["image-path"] as? String else { continue }
            let normalizedImage = normalizedLinuxImagePath(imagePath)
            guard normalizedImage == normalizedImagePath else { continue }

            guard let entities = image["system-entities"] as? [[String: Any]] else { continue }
            entityCount += entities.count
            for entity in entities {
                if let devEntry = (entity["dev-entry"] as? String) ?? (entity["devname"] as? String),
                   !devEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    devEntries.insert(devEntry)
                }
                if let mountPoint = entity["mount-point"] as? String,
                   !mountPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    mountPoints.insert(mountPoint)
                }
            }
        }

        guard entityCount > 0 else { return nil }
        return LinuxImageAttachSession(
            imagePath: normalizedImagePath,
            devEntries: Array(devEntries).sorted(),
            mountPoints: Array(mountPoints).sorted(),
            entityCount: entityCount
        )
    }

    private func normalizedLinuxImagePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
