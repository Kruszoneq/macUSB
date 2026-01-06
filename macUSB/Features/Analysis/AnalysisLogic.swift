import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine
import Foundation

final class AnalysisLogic: ObservableObject {
    // MARK: - Published State (moved from SystemAnalysisView)
    @Published var selectedFilePath: String = ""
    @Published var selectedFileUrl: URL?
    @Published var recognizedVersion: String = ""
    @Published var sourceAppURL: URL?
    @Published var mountedDMGPath: String? = nil

    @Published var isAnalyzing: Bool = false
    @Published var isSystemDetected: Bool = false
    @Published var showUSBSection: Bool = false
    @Published var showUnsupportedMessage: Bool = false

    // Flagi logiki systemowej
    @Published var needsCodesign: Bool = true
    @Published var isLegacyDetected: Bool = false
    @Published var isRestoreLegacy: Bool = false
    // NOWOŚĆ: Flaga dla Cataliny
    @Published var isCatalina: Bool = false
    @Published var isSierra: Bool = false
    @Published var isMavericks: Bool = false
    @Published var isUnsupportedSierra: Bool = false
    @Published var isPPC: Bool = false
    @Published var legacyArchInfo: String? = nil
    @Published var userSkippedAnalysis: Bool = false

    @Published var availableDrives: [USBDrive] = []
    @Published var selectedDrive: USBDrive? {
        didSet {
            // Log only when the detected/selected drive actually changes
            if oldValue?.url != selectedDrive?.url {
                let selectedPath = selectedDrive?.url.path ?? "brak"
                self.log("Wybrano dysk: \(selectedPath)")
            }
        }
    }

    @Published var isCapacitySufficient: Bool = false
    @Published var capacityCheckFinished: Bool = false

    // Computed: true only when app has recognized a supported system and can proceed normally
    var isRecognizedAndSupported: Bool {
        // Recognized and supported when analysis finished, a valid source exists or PPC flow is selected,
        // the system is detected (modern/legacy/catalina/sierra), and it's not marked unsupported.
        let recognized = (!isAnalyzing)
        let hasValidSourceOrPPC = (sourceAppURL != nil) || isPPC
        let detected = isSystemDetected || isPPC
        let unsupported = showUnsupportedMessage || isUnsupportedSierra
        return recognized && hasValidSourceOrPPC && detected && !unsupported
    }
    
    // MARK: - Helper to enumerate external hard drives (non-removable)
    private func enumerateExternalUSBHardDrives() -> [USBDrive] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeTotalCapacityKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) else { return [] }

        let candidates: [USBDrive] = urls.compactMap { url -> USBDrive? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            // Only external (non-internal), non-network, non-removable volumes (HDD/SSD)
            if (v.volumeIsInternal ?? true) { return nil }
            // Filter out obvious network-mounted volumes by scheme (e.g., afp, smb, nfs)
            let scheme = url.scheme?.lowercased()
            if let scheme = scheme, ["afp", "smb", "nfs", "ftp", "webdav"].contains(scheme) { return nil }
            if (v.volumeIsRemovable ?? false) { return nil }
            guard let name = v.volumeName else { return nil }
            let bsd = USBDriveLogic.getBSDName(from: url)
            guard !bsd.isEmpty && bsd != "unknown" else { return nil }
            let totalCapacity = Int64(v.volumeTotalCapacity ?? 0)
            let size = ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
            return USBDrive(name: name, device: bsd, size: size, url: url)
        }
        return candidates
    }

    // MARK: - Logging
    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("----------")
        print("[\(formatter.string(from: Date()))] \(message)")
    }

    // MARK: - Logic (moved from SystemAnalysisView)
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        self.log("Odebrano przeciągnięcie pliku (providers=\(providers.count)). Szukam URL...")
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    self.log("Przeciągnięto plik: \(url.path) (ext: \(url.pathExtension.lowercased()))")
                    let ext = url.pathExtension.lowercased()
                    if ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" {
                        self.processDroppedURL(url)
                    }
                }
                else if let url = item as? URL {
                    self.log("Przeciągnięto plik: \(url.path) (ext: \(url.pathExtension.lowercased()))")
                    let ext = url.pathExtension.lowercased()
                    if ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" {
                        self.processDroppedURL(url)
                    }
                }
            }
            return true
        }
        return false
    }

    func processDroppedURL(_ url: URL) {
        DispatchQueue.main.async {
            let ext = url.pathExtension.lowercased()
            self.log("Wybrano plik: \(url.path) (ext: \(ext)). Resetuję stan i przygotowuję analizę.")
            if ext == "dmg" || ext == "app" || ext == "iso" || ext == "cdr" {
                withAnimation {
                    self.selectedFilePath = url.path
                    self.selectedFileUrl = url
                    self.recognizedVersion = ""
                    self.isSystemDetected = false
                    self.sourceAppURL = nil
                    self.selectedDrive = nil
                    self.capacityCheckFinished = false
                    self.showUSBSection = false
                    self.showUnsupportedMessage = false
                    self.isSierra = false
                    self.isMavericks = false
                    self.isUnsupportedSierra = false
                    self.isPPC = false
                    self.legacyArchInfo = nil
                    self.userSkippedAnalysis = false
                }
            }
        }
    }

    func selectDMGFile() {
        self.log("Otwieram panel wyboru pliku…")
        let p = NSOpenPanel()
        p.allowedContentTypes = [.diskImage, .applicationBundle]
        // Dodajemy obsługę .iso i .cdr, które nie mają jeszcze UTType w UniformTypeIdentifiers, więc rozszerzamy allowedFileTypes
        p.allowedFileTypes = ["dmg", "iso", "cdr", "app"]
        p.allowsMultipleSelection = false
        p.begin { if $0 == .OK, let url = p.url {
            let ext = url.pathExtension.lowercased()
            guard ext == "dmg" || ext == "iso" || ext == "cdr" || ext == "app" else { return }
            withAnimation {
                self.selectedFilePath = url.path
                self.selectedFileUrl = url
                self.recognizedVersion = ""
                self.isSystemDetected = false
                self.sourceAppURL = nil
                self.selectedDrive = nil
                self.capacityCheckFinished = false
                self.showUSBSection = false
                self.showUnsupportedMessage = false
                self.isSierra = false
                self.isMavericks = false
                self.isUnsupportedSierra = false
                self.isPPC = false
                self.legacyArchInfo = nil
                self.userSkippedAnalysis = false
            }
            self.log("Wybrano plik z panelu: \(url.path) (ext: \(ext))")
        } else {
            self.log("Anulowano wybór pliku")
        } }
    }

    func startAnalysis() {
        guard let url = selectedFileUrl else { return }
        self.log("Rozpoczynam analizę pliku: \(url.path)")
        withAnimation { isAnalyzing = true }
        selectedDrive = nil; capacityCheckFinished = false
        showUSBSection = false; showUnsupportedMessage = false
        isUnsupportedSierra = false
        isPPC = false
        isMavericks = false

        let ext = url.pathExtension.lowercased()
        if ext == "dmg" || ext == "iso" || ext == "cdr" {
            self.log("Analiza obrazu (DMG/ISO/CDR): montowanie obrazu przez hdiutil (attach -plist -nobrowse -readonly), odczyt Info.plist z aplikacji oraz wykrywanie wersji i trybu instalacji.")
            let oldMountPath = self.mountedDMGPath
            DispatchQueue.global(qos: .userInitiated).async {
                if let path = oldMountPath {
                    let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); task.arguments = ["detach", path, "-force"]; try? task.run(); task.waitUntilExit()
                }
                let result = self.mountAndReadInfo(dmgUrl: url)
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.isAnalyzing = false
                        if let (_, _, _, mp) = result { self.mountedDMGPath = mp } else { self.mountedDMGPath = nil }
                        if let (name, rawVer, appURL, _) = result {
                            let friendlyVer = self.formatMarketingVersion(raw: rawVer, name: name)
                            var cleanName = name
                            cleanName = cleanName.replacingOccurrences(of: "Install ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "macOS ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "Mac OS X ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "OS X ", with: "")
                            let prefix = name.contains("macOS") ? "macOS" : (name.contains("OS X") ? "OS X" : "macOS")

                            self.recognizedVersion = "\(prefix) \(cleanName) \(friendlyVer)"
                            self.sourceAppURL = appURL

                            // Try to read ProductUserVisibleVersion from mounted image (Tiger/Leopard)
                            var userVisibleVersionFromMounted: String? = nil
                            if let mountPath = self.mountedDMGPath {
                                let sysVerPlist = URL(fileURLWithPath: mountPath).appendingPathComponent("System/Library/CoreServices/SystemVersion.plist")
                                if let data = try? Data(contentsOf: sysVerPlist),
                                   let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                                   let userVisible = dict["ProductUserVisibleVersion"] as? String {
                                    userVisibleVersionFromMounted = userVisible
                                }
                            }

                            // Use lowercase name for detection
                            let nameLower = name.lowercased()

                            // Leopard/Tiger detection (PowerPC) using name, raw version, or mounted SystemVersion.plist
                            let isLeopard = nameLower.contains("leopard") || rawVer.starts(with: "10.5") || (userVisibleVersionFromMounted?.hasPrefix("10.5") ?? false)
                            let isTiger = nameLower.contains("tiger") || rawVer.starts(with: "10.4") || (userVisibleVersionFromMounted?.hasPrefix("10.4") ?? false)
                            let isPanther = nameLower.contains("panther") || rawVer.starts(with: "10.3") || (userVisibleVersionFromMounted?.hasPrefix("10.3") ?? false)
                            let isSnowLeopard = nameLower.contains("snow leopard") || rawVer.starts(with: "10.6") || (userVisibleVersionFromMounted?.hasPrefix("10.6") ?? false)

                            // Disable kernel arch detection for Panther (10.3), Tiger (10.4), Leopard (10.5) and Snow Leopard (10.6). Always mark PPC flow for legacy, but do not set legacyArchInfo.
                            if (isLeopard || isTiger || isPanther || isSnowLeopard) {
                                self.isPPC = true // niezależnie od architektury, proces USB taki sam
                                self.legacyArchInfo = nil
                            }

                            // Legacy versions exact recognition for mounted userVisibleVersion or fallback for legacy systems
                            if isLeopard {
                                if let userVisible = userVisibleVersionFromMounted {
                                    self.recognizedVersion = "Mac OS X Leopard \(userVisible)"
                                } else if rawVer.starts(with: "10.5") {
                                    self.recognizedVersion = "Mac OS X Leopard \(rawVer)"
                                } else {
                                    self.recognizedVersion = "Mac OS X Leopard"
                                }
                            }
                            if isTiger {
                                if let userVisible = userVisibleVersionFromMounted {
                                    self.recognizedVersion = "Mac OS X Tiger \(userVisible)"
                                } else if rawVer.starts(with: "10.4") {
                                    self.recognizedVersion = "Mac OS X Tiger \(rawVer)"
                                } else {
                                    self.recognizedVersion = "Mac OS X Tiger"
                                }
                            }
                            if isPanther {
                                if let userVisible = userVisibleVersionFromMounted {
                                    self.recognizedVersion = "Mac OS X Panther \(userVisible)"
                                } else if rawVer.starts(with: "10.3") {
                                    self.recognizedVersion = "Mac OS X Panther \(rawVer)"
                                } else {
                                    self.recognizedVersion = "Mac OS X Panther"
                                }
                            }
                            if isSnowLeopard {
                                if let userVisible = userVisibleVersionFromMounted {
                                    self.recognizedVersion = "Mac OS X Snow Leopard \(userVisible)"
                                } else if rawVer.starts(with: "10.6") {
                                    self.recognizedVersion = "Mac OS X Snow Leopard \(rawVer)"
                                } else {
                                    self.recognizedVersion = "Mac OS X Snow Leopard"
                                }
                            }
                            // If Panther is detected, mark as unsupported and block further processing
                            if isPanther {
                                self.isSystemDetected = false
                                self.showUSBSection = false
                                self.isPPC = false
                                self.legacyArchInfo = nil
                                // Show unsupported message immediately
                                withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                                    self.showUnsupportedMessage = true
                                }
                                self.needsCodesign = false
                                self.isLegacyDetected = false
                                self.isRestoreLegacy = false
                                self.isCatalina = false
                                self.isSierra = false
                                self.isMavericks = false
                                self.isUnsupportedSierra = false
                                return
                            }

                            // Systemy niewspierane (Explicit) - USUNIĘTO CATALINĘ
                            let isExplicitlyUnsupported = nameLower.contains("sierra") && !nameLower.contains("high")

                            // Catalina detection
                            let isCatalina = nameLower.contains("catalina") || rawVer.starts(with: "10.15")

                            // Sierra detection (supported only for installer version 12.6.06)
                            let isSierra = (rawVer == "12.6.06")
                            let isSierraName = nameLower.contains("sierra") && !nameLower.contains("high")
                            let isUnsupportedSierraVersion = isSierraName && !isSierra

                            let isMavericks = nameLower.contains("mavericks") || rawVer.starts(with: "10.9")

                            // Modern (Big Sur+)
                            let isModern =
                                nameLower.contains("tahoe") || // Dodano Tahoe
                                nameLower.contains("sur") ||
                                nameLower.contains("monterey") ||
                                nameLower.contains("ventura") ||
                                nameLower.contains("sonoma") ||
                                nameLower.contains("sequoia") ||
                                rawVer.starts(with: "21.") || // Dodano Tahoe (v26/21.x)
                                rawVer.starts(with: "11.") ||
                                (rawVer.starts(with: "12.") && !isExplicitlyUnsupported) ||
                                (rawVer.starts(with: "13.") && !nameLower.contains("high")) ||
                                (rawVer.starts(with: "14.") && !nameLower.contains("mojave")) ||
                                (rawVer.starts(with: "15.") && !isExplicitlyUnsupported)

                            // Old Supported (Mojave + High Sierra)
                            let isOldSupported =
                                nameLower.contains("mojave") ||
                                nameLower.contains("high sierra") ||
                                rawVer.starts(with: "10.14") ||
                                rawVer.starts(with: "10.13") ||
                                (rawVer.starts(with: "14.") && nameLower.contains("mojave")) ||
                                (rawVer.starts(with: "13.") && nameLower.contains("high"))

                            // Legacy No Codesign (Yosemite + El Capitan)
                            let isLegacyDetected =
                                nameLower.contains("yosemite") ||
                                nameLower.contains("el capitan") ||
                                rawVer.starts(with: "10.10") ||
                                rawVer.starts(with: "10.11")

                            // Legacy Restore (Lion + Mountain Lion)
                            let isRestoreLegacy =
                                nameLower.contains("mountain lion") ||
                                nameLower.contains("lion") ||
                                rawVer.starts(with: "10.8") ||
                                rawVer.starts(with: "10.7")

                            // ZMIANA: Dodanie isCatalina do isSystemDetected
                            self.isSystemDetected = isModern || isOldSupported || isLegacyDetected || isRestoreLegacy || isCatalina || isSierra || isMavericks

                            // Catalina ma swój własny codesign, więc tu wyłączamy standardowy 'needsCodesign'
                            self.needsCodesign = isOldSupported && !isModern && !isLegacyDetected
                            self.isLegacyDetected = isLegacyDetected
                            self.isRestoreLegacy = isRestoreLegacy
                            self.isCatalina = isCatalina
                            self.isSierra = isSierra
                            self.isMavericks = isMavericks
                            self.isUnsupportedSierra = isUnsupportedSierraVersion
                            if isSierra {
                                self.recognizedVersion = "macOS Sierra 10.12"
                                self.needsCodesign = false
                            }
                            // Dla Leoparda/Tigera już ustawione na true powyżej, pozostaw
                            self.isPPC = self.isPPC || false

                            if self.isSystemDetected {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUSBSection = true } }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUnsupportedMessage = true } }
                            }
                            self.log("Analiza zakończona. Rozpoznano: \(self.recognizedVersion). Flagi: isCatalina=\(self.isCatalina), isSierra=\(self.isSierra), isLegacyDetected=\(self.isLegacyDetected), isRestoreLegacy=\(self.isRestoreLegacy), isPPC=\(self.isPPC), isUnsupportedSierra=\(self.isUnsupportedSierra), isMavericks=\(self.isMavericks), Mount=\(self.mountedDMGPath ?? "brak")")
                        } else {
                            // Użyto String(localized:) aby ten ciąg został wykryty, mimo że jest przypisywany do zmiennej
                            self.recognizedVersion = String(localized: "Nie rozpoznano instalatora")
                            self.log("Analiza zakończona: nie rozpoznano instalatora.")
                        }
                    }
                }
            }
        }
        else if ext == "app" {
            self.log("Analiza aplikacji (.app): odczyt Info.plist (CFBundleDisplayName, CFBundleShortVersionString) oraz wykrywanie wersji i trybu instalacji.")
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.readAppInfo(appUrl: url)
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.isAnalyzing = false
                        self.mountedDMGPath = nil
                        if let (name, rawVer, appURL) = result {
                            let friendlyVer = self.formatMarketingVersion(raw: rawVer, name: name)
                            var cleanName = name
                            cleanName = cleanName.replacingOccurrences(of: "Install ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "macOS ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "Mac OS X ", with: "")
                            cleanName = cleanName.replacingOccurrences(of: "OS X ", with: "")
                            let prefix = name.contains("macOS") ? "macOS" : (name.contains("OS X") ? "OS X" : "macOS")

                            self.recognizedVersion = "\(prefix) \(cleanName) \(friendlyVer)"
                            self.sourceAppURL = appURL

                            let nameLower = name.lowercased()

                            // Leopard detection (PowerPC)
                            let isLeopard = nameLower.contains("leopard") || rawVer.starts(with: "10.5")
                            let isTiger = nameLower.contains("tiger") || rawVer.starts(with: "10.4")
                            let isPanther = nameLower.contains("panther") || rawVer.starts(with: "10.3")
                            let isSnowLeopard = nameLower.contains("snow leopard") || rawVer.starts(with: "10.6")

                            self.legacyArchInfo = nil

                            // Dla Snow Leoparda/Leoparda/Tigera zawsze traktujemy jako PPC flow
                            if isLeopard || isTiger || isSnowLeopard {
                                self.isPPC = true
                            }

                            // Ustal dokładną wersję dla Panther/Tiger/Leopard/Snow Leopard (dla .app)
                            if isPanther || isTiger || isLeopard || isSnowLeopard {
                                let isExact = rawVer.starts(with: "10.3") || rawVer.starts(with: "10.4") || rawVer.starts(with: "10.5") || rawVer.starts(with: "10.6")
                                let exactSuffix = isExact ? " \(rawVer)" : ""
                                if isPanther {
                                    self.recognizedVersion = "Mac OS X Panther\(exactSuffix)"
                                } else if isTiger {
                                    self.recognizedVersion = "Mac OS X Tiger\(exactSuffix)"
                                } else if isLeopard {
                                    self.recognizedVersion = "Mac OS X Leopard\(exactSuffix)"
                                } else if isSnowLeopard {
                                    self.recognizedVersion = "Mac OS X Snow Leopard\(exactSuffix)"
                                }
                            }
                            // If Panther is detected, mark as unsupported and block further processing
                            if isPanther {
                                self.isSystemDetected = false
                                self.showUSBSection = false
                                self.isPPC = false
                                self.legacyArchInfo = nil
                                // Show unsupported message immediately
                                withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                                    self.showUnsupportedMessage = true
                                }
                                self.needsCodesign = false
                                self.isLegacyDetected = false
                                self.isRestoreLegacy = false
                                self.isCatalina = false
                                self.isSierra = false
                                self.isMavericks = false
                                self.isUnsupportedSierra = false
                                return
                            }

                            // Systemy niewspierane (Explicit) - USUNIĘTO CATALINĘ
                            let isExplicitlyUnsupported = nameLower.contains("sierra") && !nameLower.contains("high")

                            // Catalina detection
                            let isCatalina = nameLower.contains("catalina") || rawVer.starts(with: "10.15")

                            // Sierra detection (supported only for installer version 12.6.06)
                            let isSierra = (rawVer == "12.6.06")
                            let isSierraName = nameLower.contains("sierra") && !nameLower.contains("high")
                            let isUnsupportedSierraVersion = isSierraName && !isSierra

                            let isMavericks = nameLower.contains("mavericks") || rawVer.starts(with: "10.9")

                            // Modern (Big Sur+)
                            let isModern =
                                nameLower.contains("tahoe") || // Dodano Tahoe
                                nameLower.contains("sur") ||
                                nameLower.contains("monterey") ||
                                nameLower.contains("ventura") ||
                                nameLower.contains("sonoma") ||
                                nameLower.contains("sequoia") ||
                                rawVer.starts(with: "21.") || // Dodano Tahoe (v26/21.x)
                                rawVer.starts(with: "11.") ||
                                (rawVer.starts(with: "12.") && !isExplicitlyUnsupported) ||
                                (rawVer.starts(with: "13.") && !nameLower.contains("high")) ||
                                (rawVer.starts(with: "14.") && !nameLower.contains("mojave")) ||
                                (rawVer.starts(with: "15.") && !isExplicitlyUnsupported)

                            // Old Supported (Mojave + High Sierra)
                            let isOldSupported =
                                nameLower.contains("mojave") ||
                                nameLower.contains("high sierra") ||
                                rawVer.starts(with: "10.14") ||
                                rawVer.starts(with: "10.13") ||
                                (rawVer.starts(with: "14.") && nameLower.contains("mojave")) ||
                                (rawVer.starts(with: "13.") && nameLower.contains("high"))

                            // Legacy No Codesign (Yosemite + El Capitan)
                            let isLegacyDetected =
                                nameLower.contains("yosemite") ||
                                nameLower.contains("el capitan") ||
                                rawVer.starts(with: "10.10") ||
                                rawVer.starts(with: "10.11")

                            // Legacy Restore (Lion + Mountain Lion)
                            let isRestoreLegacy =
                                nameLower.contains("mountain lion") ||
                                nameLower.contains("lion") ||
                                rawVer.starts(with: "10.8") ||
                                rawVer.starts(with: "10.7")

                            self.isSystemDetected = isModern || isOldSupported || isLegacyDetected || isRestoreLegacy || isCatalina || isSierra

                            self.needsCodesign = isOldSupported && !isModern && !isLegacyDetected
                            self.isLegacyDetected = isLegacyDetected
                            self.isRestoreLegacy = isRestoreLegacy
                            self.isCatalina = isCatalina
                            self.isSierra = isSierra
                            self.isMavericks = isMavericks
                            self.isUnsupportedSierra = isUnsupportedSierraVersion
                            if isSierra {
                                self.recognizedVersion = "macOS Sierra 10.12"
                                self.needsCodesign = false
                            }
                            // isPPC zostało ustawione wcześniej dla Snow Leoparda/Leoparda/Tigera; dla pozostałych pozostaje false
                            self.isPPC = self.isPPC || false

                            if self.isSystemDetected {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUSBSection = true } }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUnsupportedMessage = true } }
                            }
                            self.log("Analiza zakończona. Rozpoznano: \(self.recognizedVersion). Flagi: isCatalina=\(self.isCatalina), isSierra=\(self.isSierra), isLegacyDetected=\(self.isLegacyDetected), isRestoreLegacy=\(self.isRestoreLegacy), isPPC=\(self.isPPC), isUnsupportedSierra=\(self.isUnsupportedSierra), isMavericks=\(self.isMavericks)")
                        } else {
                            self.recognizedVersion = String(localized: "Nie rozpoznano instalatora")
                            self.log("Analiza zakończona: nie rozpoznano instalatora.")
                        }
                    }
                }
            }
        }
    }

    func forceTigerMultiDVDSelection() {
        self.log("Ręcznie wybrano tryb Tiger Multi DVD")
        let fileURL = self.selectedFileUrl
        DispatchQueue.global(qos: .userInitiated).async {
            var mountPoint: String? = self.mountedDMGPath
            var effectiveSourceAppURL: URL? = nil
            if let url = fileURL {
                let ext = url.pathExtension.lowercased()
                if ext == "dmg" || ext == "iso" || ext == "cdr" {
                    if mountPoint == nil {
                        mountPoint = self.mountImageForPPC(dmgUrl: url)
                    }
                    if let mp = mountPoint {
                        effectiveSourceAppURL = URL(fileURLWithPath: mp).appendingPathComponent("Install")
                    }
                } else if ext == "app" {
                    effectiveSourceAppURL = url
                }
            }
            DispatchQueue.main.async {
                withAnimation {
                    self.isAnalyzing = false
                    self.userSkippedAnalysis = true
                    self.recognizedVersion = "Mac OS X Tiger 10.4"
                    self.sourceAppURL = effectiveSourceAppURL
                    self.mountedDMGPath = mountPoint
                    self.isSystemDetected = true
                    self.showUnsupportedMessage = false
                    self.showUSBSection = true
                    self.needsCodesign = false
                    self.isLegacyDetected = false
                    self.isRestoreLegacy = false
                    self.isCatalina = false
                    self.isSierra = false
                    self.isMavericks = false
                    self.isUnsupportedSierra = false
                    self.isPPC = true
                    self.legacyArchInfo = nil
                    self.selectedDrive = nil
                    self.capacityCheckFinished = false
                }
                self.log("Ustawiono Tiger Multi DVD: recognizedVersion=\(self.recognizedVersion), mount=\(self.mountedDMGPath ?? "brak"), isPPC=\(self.isPPC)")
            }
        }
    }

    func formatMarketingVersion(raw: String, name: String) -> String {
        let n = name.lowercased()
        if n.contains("tahoe") { return "26" } // Dodano Tahoe
        if n.contains("sequoia") { return "15" }
        if n.contains("sonoma") { return "14" }
        if n.contains("ventura") { return "13" }
        if n.contains("monterey") { return "12" }
        if n.contains("big sur") { return "11" }
        if n.contains("catalina") { return "10.15" }
        if n.contains("mojave") { return "10.14" }
        if n.contains("high sierra") { return "10.13" }
        if n.contains("sierra") && !n.contains("high") { return "10.12" }
        if n.contains("el capitan") { return "10.11" }
        if n.contains("yosemite") { return "10.10" }
        if n.contains("mavericks") { return "10.9" }
        if n.contains("mountain lion") { return "10.8" }
        if n.contains("lion") { return "10.7" }
        if n.contains("snow leopard") { return "10.6" }
        if n.contains("panther") { return "10.3" }
        return raw
    }

    func readAppInfo(appUrl: URL) -> (String, String, URL)? {
        let plistUrl = appUrl.appendingPathComponent("Contents/Info.plist")
        if let d = try? Data(contentsOf: plistUrl),
           let dict = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
            let name = (dict["CFBundleDisplayName"] as? String) ?? appUrl.lastPathComponent
            let ver = (dict["CFBundleShortVersionString"] as? String) ?? "?"
            return (name, ver, appUrl)
        }
        return nil
    }

    func mountAndReadInfo(dmgUrl: URL) -> (String, String, URL, String)? {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", dmgUrl.path, "-plist", "-nobrowse", "-readonly"]
        let pipe = Pipe(); task.standardOutput = pipe; try? task.run(); task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let entities = plist["system-entities"] as? [[String: Any]] else { return nil }
        for e in entities {
            if let mp = e["mount-point"] as? String {
                let mUrl = URL(fileURLWithPath: mp)
                if let item = try? FileManager.default.contentsOfDirectory(at: mUrl, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) {
                    let plistUrl = item.appendingPathComponent("Contents/Info.plist")
                    if let d = try? Data(contentsOf: plistUrl), let dict = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
                        let name = (dict["CFBundleDisplayName"] as? String) ?? item.lastPathComponent
                        let ver = (dict["CFBundleShortVersionString"] as? String) ?? "?"
                        return (name, ver, item, mp)
                    }
                }
            }
        }
        return nil
    }

    func mountImageForPPC(dmgUrl: URL) -> String? {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", dmgUrl.path, "-plist", "-nobrowse", "-readonly"]
        let pipe = Pipe(); task.standardOutput = pipe; try? task.run(); task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let entities = plist["system-entities"] as? [[String: Any]] else { return nil }
        for e in entities {
            if let mp = e["mount-point"] as? String { return mp }
        }
        return nil
    }

    func refreshDrives() {
        let currentSelectedURL = selectedDrive?.url
        var foundDrives = USBDriveLogic.enumerateAvailableDrives()
        let allowExternal = UserDefaults.standard.bool(forKey: "AllowExternalDrives")
        if allowExternal {
            let extra = enumerateExternalUSBHardDrives()
            // Merge unique by URL
            for d in extra {
                if !foundDrives.contains(where: { $0.url == d.url }) {
                    foundDrives.append(d)
                }
            }
        }
        self.availableDrives = foundDrives
        if let currentURL = currentSelectedURL {
            if let stillConnectedDrive = foundDrives.first(where: { $0.url == currentURL }) {
                self.selectedDrive = stillConnectedDrive
            } else {
                self.selectedDrive = nil
                self.capacityCheckFinished = false
            }
        } else {
            if self.selectedDrive != nil {
                self.selectedDrive = nil
                self.capacityCheckFinished = false
            }
        }
    }

    func checkCapacity() {
        guard let drive = selectedDrive else { capacityCheckFinished = false; return }
        if let values = try? drive.url.resourceValues(forKeys: [.volumeTotalCapacityKey]), let capacity = values.volumeTotalCapacity {
            let minCapacity: Int = 15_000_000_000
            withAnimation { isCapacitySufficient = capacity >= minCapacity; capacityCheckFinished = true }
        } else { isCapacitySufficient = false; capacityCheckFinished = true }
    }

    func resetAll() {
        let oldMount = self.mountedDMGPath
        if let path = oldMount {
            let task = Process()
            task.launchPath = "/usr/bin/hdiutil"
            task.arguments = ["detach", path, "-force"]
            try? task.run()
            task.waitUntilExit()
        }
        DispatchQueue.main.async {
            withAnimation {
                self.selectedFilePath = ""
                self.selectedFileUrl = nil
                self.recognizedVersion = ""
                self.sourceAppURL = nil
                self.mountedDMGPath = nil

                self.isAnalyzing = false
                self.isSystemDetected = false
                self.showUSBSection = false
                self.showUnsupportedMessage = false

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

                self.availableDrives = []
                self.selectedDrive = nil

                self.isCapacitySufficient = false
                self.capacityCheckFinished = false
            }
        }
    }

    // Call this from the UI when the user presses the "Przejdź dalej" button
    func recordProceedPressed() {
        self.log("Użytkownik nacisnął przycisk 'Przejdź dalej'. Wybrany dysk: \(self.selectedDrive?.url.path ?? "brak"), źródło: \(self.sourceAppURL?.path ?? "brak"), rozpoznano: \(self.recognizedVersion)")
    }
}

extension Notification.Name {
    static let macUSBResetToStart = Notification.Name("macUSB.resetToStart")
    static let macUSBStartTigerMultiDVD = Notification.Name("macUSB.startTigerMultiDVD")
}

