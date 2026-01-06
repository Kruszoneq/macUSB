import Foundation

struct USBDriveLogic {
    /// Returns true if the mounted volume at the given URL is a network filesystem.
    private static func isNetworkVolume(url: URL) -> Bool {
        return url.withUnsafeFileSystemRepresentation { ptr in
            guard let ptr = ptr else { return false }
            var stat = statfs()
            if statfs(ptr, &stat) == 0 {
                // Extract filesystem type name (e.g., "apfs", "smbfs", "webdav", "afpfs")
                let fsName = withUnsafePointer(to: &stat.f_fstypename) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                        String(cString: $0)
                    }
                }.lowercased()
                // Common network filesystem types
                let networkTypes: Set<String> = ["smbfs", "afpfs", "webdav", "nfs", "cifs"]
                return networkTypes.contains(fsName)
            }
            return false
        } ?? false
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
            return USBDrive(name: name, device: deviceName, size: size, url: url)
        }
        return drives
    }
}
