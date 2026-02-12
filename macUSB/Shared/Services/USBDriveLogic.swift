import Foundation
import IOKit
import IOKit.storage
import IOKit.usb

struct USBDriveLogic {
    /// Zwraca nazwę dysku bazowego (np. z "disk2s1" -> "disk2")
    static func wholeDiskName(from bsd: String) -> String {
        if let range = bsd.range(of: #"^disk\d+"#, options: .regularExpression) {
            return String(bsd[range])
        }
        return bsd
    }

    /// Odczytuje właściwość z IORegistry jako Any
    private static func ioRegistryProperty(_ entry: io_registry_entry_t, key: String) -> Any? {
        let cfKey = key as CFString
        if let cfProp = IORegistryEntryCreateCFProperty(entry, cfKey, kCFAllocatorDefault, 0)?.takeRetainedValue() {
            return cfProp
        }
        return nil
    }

    /// Wykrywa schemat partycji dla whole-disk o nazwie BSD (np. disk2)
    static func detectPartitionScheme(forBSDName bsdWholeName: String) -> PartitionScheme? {
        var iterator: io_iterator_t = 0
        guard let match = IOServiceMatching("IOMedia") else { return nil }
        if IOServiceGetMatchingServices(0, match, &iterator) != KERN_SUCCESS { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }

            let bsdName = ioRegistryProperty(service, key: kIOBSDNameKey as String) as? String
            let isWhole = (ioRegistryProperty(service, key: kIOMediaWholeKey as String) as? NSNumber)?.boolValue ?? false
            guard bsdName == bsdWholeName, isWhole else { continue }

            let content = (ioRegistryProperty(service, key: kIOMediaContentKey as String) as? String)?.lowercased()
            switch content {
            case "guid_partition_scheme":
                return .gpt
            case "apple_partition_scheme":
                return .apm
            case "fdisk_partition_scheme":
                return .mbr
            case .some:
                return .unknown
            case .none:
                return nil
            }
        }
        return nil
    }

    /// Przechodzi po rodzicach w płaszczyźnie kIOServicePlane aż do korzenia, zwracając wykryty standard USB
    static func detectUSBSpeed(forBSDName bsdWholeName: String) -> USBPortSpeed? {
        // Wyszukaj w IORegistry węzeł IOMedia odpowiadający whole disk o nazwie BSD
        var iterator: io_iterator_t = 0
        guard let match = IOServiceMatching("IOMedia") else { return nil }
        // Pobierz wszystkie IOMedia i przefiltruj we własnym zakresie
        if IOServiceGetMatchingServices(0, match, &iterator) != KERN_SUCCESS { return nil }
        defer { IOObjectRelease(iterator) }

        var media: io_object_t = IO_OBJECT_NULL
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            // Sprawdź nazwę BSD i czy to whole media
            let bsdName = ioRegistryProperty(service, key: kIOBSDNameKey as String) as? String
            let isWhole = (ioRegistryProperty(service, key: kIOMediaWholeKey as String) as? NSNumber)?.boolValue ?? false
            if bsdName == bsdWholeName && isWhole {
                // Wspinaj się po rodzicach i szukaj węzłów USB
                var current: io_registry_entry_t = service
                while true {
                    var parent: io_registry_entry_t = IO_OBJECT_NULL
                    let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
                    if kr != KERN_SUCCESS || parent == IO_OBJECT_NULL { break }

                    // Spróbuj odczytać bcdUSB
                    if let bcd = ioRegistryProperty(parent, key: "bcdUSB") as? NSNumber {
                        let value = bcd.intValue
                        if value >= 0x0400 { IOObjectRelease(parent); return .usb4 }
                        if value >= 0x0320 { IOObjectRelease(parent); return .usb32 }
                        if value >= 0x0310 { IOObjectRelease(parent); return .usb31 }
                        if value >= 0x0300 { IOObjectRelease(parent); return .usb3 }
                        if value >= 0x0200 { IOObjectRelease(parent); return .usb2 }
                    }
                    // Spróbuj odczytać PortSpeed (np. "High Speed", "SuperSpeed")
                    if let speedStr = ioRegistryProperty(parent, key: "PortSpeed") as? String {
                        let s = speedStr.lowercased()
                        if s.contains("superspeed") { IOObjectRelease(parent); return .usb3 }
                        if s.contains("high speed") { IOObjectRelease(parent); return .usb2 }
                    }

                    IOObjectRelease(current)
                    current = parent
                }
                if current != IO_OBJECT_NULL { IOObjectRelease(current) }
                break
            }
        }
        return nil
    }

    /// Returns true if the mounted volume at the given URL is a network filesystem.
    private static func isNetworkVolume(url: URL) -> Bool {
        guard let fsName = fileSystemTypeName(url: url) else { return false }
        let networkTypes: Set<String> = ["smbfs", "afpfs", "webdav", "nfs", "cifs"]
        return networkTypes.contains(fsName)
    }

    /// Returns a normalized filesystem type name from statfs (e.g. apfs, hfs, exfat).
    private static func fileSystemTypeName(url: URL) -> String? {
        return url.withUnsafeFileSystemRepresentation { ptr in
            guard let ptr = ptr else { return nil }
            var stat = statfs()
            guard statfs(ptr, &stat) == 0 else { return nil }
            return withUnsafePointer(to: &stat.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                    String(cString: $0)
                }
            }.lowercased()
        } ?? nil
    }

    /// Wykrywa format systemu plików dla zamontowanego woluminu.
    static func detectFileSystemFormat(forVolumeURL url: URL) -> FileSystemFormat? {
        guard let fsName = fileSystemTypeName(url: url) else { return nil }
        switch fsName {
        case "apfs":
            return .apfs
        case "hfs":
            return .hfsPlus
        case "exfat":
            return .exfat
        case "msdos":
            return .fat
        case "ntfs":
            return .ntfs
        default:
            return .unknown
        }
    }

    /// Returns the BSD device name (e.g., "disk2s1") for a mounted volume URL.
    static func getBSDName(from url: URL) -> String {
        return url.withUnsafeFileSystemRepresentation { ptr in
            guard let ptr = ptr else { return "unknown" }
            var stat = statfs()
            if statfs(ptr, &stat) == 0 {
                var raw = stat.f_mntfromname
                return withUnsafePointer(to: &raw) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                        String(cString: $0).replacingOccurrences(of: "/dev/", with: "")
                    }
                }
            }
            return "unknown"
        } ?? "unknown"
    }

    /// Enumerates external, non-internal, non-network removable mounted volumes and returns them as USBDrive models.
    static func enumerateAvailableDrives() -> [USBDrive] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeTotalCapacityKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: .skipHiddenVolumes
        ) else { return [] }

        let drives: [USBDrive] = urls.compactMap { url -> USBDrive? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let isRemovable = v.volumeIsRemovable, isRemovable,
                  let isInternal = v.volumeIsInternal, !isInternal,
                  let name = v.volumeName else {
                return nil
            }
            if isNetworkVolume(url: url) {
                return nil
            }
            let totalCapacity = Int64(v.volumeTotalCapacity ?? 0)
            let size = ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
            let deviceName = getBSDName(from: url)
            let whole = wholeDiskName(from: deviceName)
            let speed = detectUSBSpeed(forBSDName: whole)
            let partitionScheme = detectPartitionScheme(forBSDName: whole)
            let fileSystemFormat = detectFileSystemFormat(forVolumeURL: url)
            return USBDrive(
                name: name,
                device: deviceName,
                size: size,
                url: url,
                usbSpeed: speed,
                partitionScheme: partitionScheme,
                fileSystemFormat: fileSystemFormat
            )
        }
        return drives
    }
}
