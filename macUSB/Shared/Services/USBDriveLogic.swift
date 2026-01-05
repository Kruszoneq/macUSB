import Foundation

struct USBDriveLogic {
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
    
    /// Checks if a volume is a network  drive
    static func isNetworkVolume(_ url: URL) -> Bool {
        return url.withUnsafeFileSystemRepresentation { ptr in
            guard let ptr = ptr else { return true }
            var stat = statfs()
            if statfs(ptr, &stat) == 0 {
                var raw = stat.f_mntfromname
                let mntFrom = withUnsafePointer(to: &raw) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                        String(cString: $0)
                    }
                }
                let networkPrefixes = ["smb://", "afp://", "nfs://", "cifs://", "webdav://", "ftp://"]
                if networkPrefixes.contains(where: { mntFrom.lowercased().hasPrefix($0) }) {
                    return true
                }
                if !mntFrom.hasPrefix("/dev/") {
                    return true
                }
            }
            return false
        } ?? true
    }
    
    /// Checks if a volume is a virtual disk image rather than a physical drive
    static func isVirtualDiskImage(_ url: URL) -> Bool {
        return url.withUnsafeFileSystemRepresentation { ptr in
            guard let ptr = ptr else { return true }
            var stat = statfs()
            if statfs(ptr, &stat) == 0 {
                let mountPath = url.path.lowercased()
                if mountPath.contains(".dmg") || mountPath.contains("disk image") {
                    return true
                }
            }
            return false
        } ?? true
    }

    /// Enumerates external USB drives (including SSDs/HDDs) while excluding internal drives and network volumes.
    /// - Parameter includeLargeDrives: If true, includes external SSDs/HDDs (ejectable). If false, only shows removable USB sticks.
    static func enumerateAvailableDrives(includeLargeDrives: Bool = true) -> [USBDrive] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey,
            .volumeTotalCapacityKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: .skipHiddenVolumes
        ) else { return [] }

        let drives: [USBDrive] = urls.compactMap { url -> USBDrive? in
            if isNetworkVolume(url) {
                return nil
            }
            
            if isVirtualDiskImage(url) {
                return nil
            }
            
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let isInternal = v.volumeIsInternal,
                  !isInternal,
                  let name = v.volumeName else {
                return nil
            }
            
            let isRemovable = v.volumeIsRemovable ?? false
            let isEjectable = v.volumeIsEjectable ?? false
            
            let deviceName = getBSDName(from: url)
            guard deviceName != "unknown" && deviceName.hasPrefix("disk") else {
                return nil
            }
            
            if !includeLargeDrives {
                guard isRemovable else {
                    return nil
                }
            } else {
                if !isRemovable && !isEjectable {
                    // Accept external drives with valid BSD name even if not marked removable/ejectable
                }
            }
            
            let totalCapacity = Int64(v.volumeTotalCapacity ?? 0)
            let size = ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
            return USBDrive(name: name, device: deviceName, size: size, url: url)
        }
        return drives
    }
}
