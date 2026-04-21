import SwiftUI
import Foundation

extension AnalysisLogic {
    private var requiredUSBCapacityBytes: Int? {
        guard let requiredGB = requiredUSBCapacityGB else { return nil }
        switch requiredGB {
        case 8:
            return 6_000_000_000
        case 16:
            return 15_000_000_000
        case 32:
            return 28_000_000_000
        default:
            return requiredGB * 1_000_000_000
        }
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
            let whole = USBDriveLogic.wholeDiskName(from: bsd)
            let speed = USBDriveLogic.detectUSBSpeed(forBSDName: whole)
            let partitionScheme = USBDriveLogic.detectPartitionScheme(forBSDName: whole)
            let fileSystemFormat = USBDriveLogic.detectFileSystemFormat(forVolumeURL: url)
            return USBDrive(
                name: name,
                device: bsd,
                size: size,
                url: url,
                usbSpeed: speed,
                partitionScheme: partitionScheme,
                fileSystemFormat: fileSystemFormat
            )
        }
        return candidates
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
        guard let drive = selectedDrive, let minCapacity = requiredUSBCapacityBytes else {
            isCapacitySufficient = false
            capacityCheckFinished = false
            return
        }
        if let values = try? drive.url.resourceValues(forKeys: [.volumeTotalCapacityKey]), let capacity = values.volumeTotalCapacity {
            withAnimation { isCapacitySufficient = capacity >= minCapacity; capacityCheckFinished = true }
        } else {
            isCapacitySufficient = false
            capacityCheckFinished = true
        }
    }
}
