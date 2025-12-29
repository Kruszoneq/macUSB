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
    @Published var isUnsupportedSierra: Bool = false
    @Published var isPPC: Bool = false
    @Published var legacyArchInfo: String? = nil

    @Published var availableDrives: [USBDrive] = []
    @Published var selectedDrive: USBDrive?

    @Published var isCapacitySufficient: Bool = false
    @Published var capacityCheckFinished: Bool = false

    // MARK: - Logic (moved from SystemAnalysisView)
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    let ext = url.pathExtension.lowercased()
                    if ext == "dmg" || ext == "app" || ext == "iso" {
                        self.processDroppedURL(url)
                    }
                }
                else if let url = item as? URL {
                    let ext = url.pathExtension.lowercased()
                    if ext == "dmg" || ext == "app" || ext == "iso" {
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
            if ext == "dmg" || ext == "app" || ext == "iso" {
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
                    self.isUnsupportedSierra = false
                    self.isPPC = false
                    self.legacyArchInfo = nil
                }
            }
        }
    }

    func selectDMGFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.diskImage, .applicationBundle]
        // Dodajemy obsługę .iso, który nie ma jeszcze UTType w UniformTypeIdentifiers, więc rozszerzamy allowedFileTypes
        p.allowedFileTypes = ["dmg", "iso", "app"]
        p.allowsMultipleSelection = false
        p.begin { if $0 == .OK, let url = p.url {
            let ext = url.pathExtension.lowercased()
            guard ext == "dmg" || ext == "iso" || ext == "app" else { return }
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
                self.isUnsupportedSierra = false
                self.isPPC = false
                self.legacyArchInfo = nil
            }
        }}
    }

    func startAnalysis() {
        guard let url = selectedFileUrl else { return }
        withAnimation { isAnalyzing = true }
        selectedDrive = nil; capacityCheckFinished = false
        showUSBSection = false; showUnsupportedMessage = false
        isUnsupportedSierra = false
        isPPC = false

        let ext = url.pathExtension.lowercased()
        if ext == "dmg" || ext == "iso" {
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

                            if isLeopard {
                                if let userVisible = userVisibleVersionFromMounted {
                                    self.recognizedVersion = "Mac OS X Leopard \(userVisible)"
                                } else {
                                    self.recognizedVersion = "Mac OS X Leopard"
                                }
                            }
                            if isTiger {
                                if let userVisible = userVisibleVersionFromMounted {
                                    self.recognizedVersion = "Mac OS X Tiger \(userVisible)"
                                } else {
                                    self.recognizedVersion = "Mac OS X Tiger"
                                }
                            }

                            // Detect architecture from mach_kernel for Tiger/Leopard and always mark as PPC flow
                            if (isLeopard || isTiger) {
                                self.isPPC = true // niezależnie od architektury, proces USB taki sam
                                if let mountPath = self.mountedDMGPath {
                                    if let rawArch = self.detectLegacyKernelArch(at: URL(fileURLWithPath: mountPath)) {
                                        let arch: String = (rawArch == "Universal") ? "PowerPC + Intel" : (rawArch == "PPC" ? "PowerPC" : "Intel")
                                        self.legacyArchInfo = arch
                                        self.recognizedVersion += " - \(arch)"
                                    }
                                }
                            }

                            // Systemy niewspierane (Explicit) - USUNIĘTO CATALINĘ
                            let isExplicitlyUnsupported = nameLower.contains("sierra") && !nameLower.contains("high")

                            // Catalina detection
                            let isCatalina = nameLower.contains("catalina") || rawVer.starts(with: "10.15")

                            // Sierra detection (supported only for installer version 12.6.06)
                            let isSierra = (rawVer == "12.6.06")
                            let isSierraName = nameLower.contains("sierra") && !nameLower.contains("high")
                            let isUnsupportedSierraVersion = isSierraName && !isSierra

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
                            self.isSystemDetected = isModern || isOldSupported || isLegacyDetected || isRestoreLegacy || isCatalina || isSierra

                            // Catalina ma swój własny codesign, więc tu wyłączamy standardowy 'needsCodesign'
                            self.needsCodesign = isOldSupported && !isModern && !isLegacyDetected
                            self.isLegacyDetected = isLegacyDetected
                            self.isRestoreLegacy = isRestoreLegacy
                            self.isCatalina = isCatalina
                            self.isSierra = isSierra
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
                        } else {
                            // Użyto String(localized:) aby ten ciąg został wykryty, mimo że jest przypisywany do zmiennej
                            self.recognizedVersion = String(localized: "Nie rozpoznano instalatora")
                        }
                    }
                }
            }
        }
        else if ext == "app" {
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

                            self.legacyArchInfo = nil

                            // Dla Leoparda/Tigera zawsze traktujemy jako PPC flow
                            if isLeopard || isTiger {
                                self.isPPC = true
                            }

                            // Systemy niewspierane (Explicit) - USUNIĘTO CATALINĘ
                            let isExplicitlyUnsupported = nameLower.contains("sierra") && !nameLower.contains("high")

                            // Catalina detection
                            let isCatalina = nameLower.contains("catalina") || rawVer.starts(with: "10.15")

                            // Sierra detection (supported only for installer version 12.6.06)
                            let isSierra = (rawVer == "12.6.06")
                            let isSierraName = nameLower.contains("sierra") && !nameLower.contains("high")
                            let isUnsupportedSierraVersion = isSierraName && !isSierra

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
                            self.isUnsupportedSierra = isUnsupportedSierraVersion
                            if isSierra {
                                self.recognizedVersion = "macOS Sierra 10.12"
                                self.needsCodesign = false
                            }
                            // isPPC zostało ustawione wcześniej dla Leoparda/Tigera; dla pozostałych pozostaje false
                            self.isPPC = self.isPPC || false

                            if self.isSystemDetected {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUSBSection = true } }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUnsupportedMessage = true } }
                            }
                        } else {
                            self.recognizedVersion = String(localized: "Nie rozpoznano instalatora")
                        }
                    }
                }
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

    func refreshDrives() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeTotalCapacityKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) else { return }
        let currentSelectedURL = selectedDrive?.url
        let foundDrives = urls.compactMap { url -> USBDrive? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), let isRemovable = v.volumeIsRemovable, isRemovable, let isInternal = v.volumeIsInternal, !isInternal, let name = v.volumeName else { return nil }
            let size = ByteCountFormatter.string(fromByteCount: Int64(v.volumeTotalCapacity ?? 0), countStyle: .file)
            let deviceName = self.getBSDName(from: url)
            return USBDrive(name: name, device: deviceName, size: size, url: url)
        }
        self.availableDrives = foundDrives
        if let currentURL = currentSelectedURL {
            if let stillConnectedDrive = foundDrives.first(where: { $0.url == currentURL }) { self.selectedDrive = stillConnectedDrive } else { self.selectedDrive = nil; self.capacityCheckFinished = false }
        } else { if self.selectedDrive != nil { self.selectedDrive = nil; self.capacityCheckFinished = false } }
    }

    func checkCapacity() {
        guard let drive = selectedDrive else { capacityCheckFinished = false; return }
        if let values = try? drive.url.resourceValues(forKeys: [.volumeTotalCapacityKey]), let capacity = values.volumeTotalCapacity {
            let minCapacity: Int = 15_000_000_000
            withAnimation { isCapacitySufficient = capacity >= minCapacity; capacityCheckFinished = true }
        } else { isCapacitySufficient = false; capacityCheckFinished = true }
    }

    func getBSDName(from url: URL) -> String {
        return url.withUnsafeFileSystemRepresentation { ptr in
            guard let ptr = ptr else { return "unknown" }
            var stat = statfs(); if statfs(ptr, &stat) == 0 { var raw = stat.f_mntfromname; return withUnsafePointer(to: &raw) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0).replacingOccurrences(of: "/dev/", with: "") } } }
            return "unknown"
        } ?? "unknown"
    }

    /// Attempts to detect architecture of legacy OS X kernel by inspecting the mach_kernel file located at the root of the mounted volume.
    /// Returns "PPC", "Intel", or "Universal" when determinable; otherwise nil.
    func detectLegacyKernelArch(at mountURL: URL) -> String? {
        let kernelURL = mountURL.appendingPathComponent("mach_kernel")
        guard let data = try? Data(contentsOf: kernelURL) else { return nil }
        // Mach-O magic constants
        let MH_MAGIC: UInt32 = 0xfeedface
        let MH_CIGAM: UInt32 = 0xcefaedfe
        let MH_MAGIC_64: UInt32 = 0xfeedfacf
        let MH_CIGAM_64: UInt32 = 0xcffaedfe
        let FAT_MAGIC: UInt32 = 0xcafebabe
        let FAT_CIGAM: UInt32 = 0xbebafeca

        func readUInt32(_ offset: Int) -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            return data.withUnsafeBytes { ptr in ptr.load(fromByteOffset: offset, as: UInt32.self) }
        }

        func swap32(_ x: UInt32) -> UInt32 { return (x << 24) | ((x << 8) & 0x00FF0000) | ((x >> 8) & 0x0000FF00) | (x >> 24) }

        // CPU type constants
        let CPU_TYPE_I386: UInt32 = 7
        let CPU_TYPE_POWERPC: UInt32 = 18

        guard let magic = readUInt32(0) else { return nil }

        // Helper to interpret a single Mach-O header and return architecture string
        func archForMachO(at offset: Int, swapped: Bool) -> String? {
            guard let cputypeRaw = readUInt32(offset + 4) else { return nil }
            let cputype = swapped ? swap32(cputypeRaw) : cputypeRaw
            if cputype == CPU_TYPE_POWERPC { return "PPC" }
            if cputype == CPU_TYPE_I386 { return "Intel" }
            return nil
        }

        // Thin Mach-O
        if magic == MH_MAGIC || magic == MH_MAGIC_64 {
            return archForMachO(at: 0, swapped: false)
        }
        if magic == MH_CIGAM || magic == MH_CIGAM_64 {
            return archForMachO(at: 0, swapped: true)
        }

        // Fat binary
        if magic == FAT_MAGIC || magic == FAT_CIGAM {
            let swapped = (magic == FAT_CIGAM)
            guard let nfatRaw = readUInt32(4) else { return nil }
            let nfat = Int(swapped ? swap32(nfatRaw) : nfatRaw)
            var hasPPC = false
            var hasIntel = false
            var offset = 8
            for _ in 0..<nfat {
                guard let cputypeRaw = readUInt32(offset) else { break }
                let cputype = swapped ? swap32(cputypeRaw) : cputypeRaw
                if cputype == CPU_TYPE_POWERPC { hasPPC = true }
                if cputype == CPU_TYPE_I386 { hasIntel = true }
                offset += 20 // sizeof(struct fat_arch) = 5 * UInt32
            }
            if hasPPC && hasIntel { return "Universal" }
            if hasPPC { return "PPC" }
            if hasIntel { return "Intel" }
        }

        return nil
    }
}
