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
        let allowExternal = UserDefaults.standard.bool(forKey: "AllowExternalDrives")

        if isLinuxDetected || isWindowsWorkflowSupported {
            guard !isLinuxPhysicalDriveRefreshRunning else { return }
            isLinuxPhysicalDriveRefreshRunning = true

            DispatchQueue.global(qos: .utility).async { [weak self] in
                let enumerated = USBDriveLogic.enumerateAvailablePhysicalUSBDrivesWithCapacities(
                    allowExternalHardDrives: allowExternal
                )

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isLinuxPhysicalDriveRefreshRunning = false

                    guard self.isLinuxDetected || self.isWindowsWorkflowSupported else { return }

                    self.linuxWholeDiskCapacityCache = enumerated.capacityByWholeDisk
                    let activeSelectionID = self.selectedDriveSelectionID ?? self.selectedDrive?.selectionID
                    let resolvedSelection = activeSelectionID.flatMap { selectionID in
                        enumerated.drives.first(where: { $0.selectionID == selectionID })
                    }

                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.synchronizeDriveSelection {
                            self.availableDrives = enumerated.drives
                            self.selectedDrive = resolvedSelection
                            self.selectedDriveSelectionID = resolvedSelection?.selectionID
                        }
                    }

                    if resolvedSelection == nil {
                        self.capacityCheckFinished = false
                    }

                    self.isUnreadableUSBDetectionRunning = false
                    self.unreadableExternalUSBMediaCount = 0
                    self.hasUnreadableExternalUSBMedia = false

                    if self.selectedDrive != nil {
                        self.checkCapacity()
                    }
                }
            }
            return
        } else {
            linuxWholeDiskCapacityCache = [:]
        }

        let currentSelectedSelectionID = selectedDriveSelectionID ?? selectedDrive?.selectionID
        var volumeDrives = USBDriveLogic.enumerateAvailableDrives()
        if allowExternal {
            let extra = enumerateExternalUSBHardDrives()
            // Merge unique by URL
            for d in extra {
                if !volumeDrives.contains(where: { $0.url == d.url }) {
                    volumeDrives.append(d)
                }
            }
        }
        let foundDrives = volumeDrives

        let resolvedSelection = currentSelectedSelectionID.flatMap { selectionID in
            foundDrives.first(where: { $0.selectionID == selectionID })
        }

        synchronizeDriveSelection {
            self.availableDrives = foundDrives
            self.selectedDrive = resolvedSelection
            self.selectedDriveSelectionID = resolvedSelection?.selectionID
        }

        if resolvedSelection == nil {
            self.capacityCheckFinished = false
        }

        refreshUnreadableExternalUSBMediaIfNeeded()
    }

    func refreshUnreadableExternalUSBMediaIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastUnreadableUSBDetectionDate) >= unreadableUSBDetectionInterval else {
            return
        }
        guard !isUnreadableUSBDetectionRunning else { return }

        lastUnreadableUSBDetectionDate = now
        isUnreadableUSBDetectionRunning = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let unreadableCount = USBDriveLogic.unreadableExternalUSBMediaCount()

            DispatchQueue.main.async {
                guard let self else { return }
                self.isUnreadableUSBDetectionRunning = false

                if self.unreadableExternalUSBMediaCount != unreadableCount {
                    self.log(
                        "Wykryto nieczytelne nośniki USB: \(unreadableCount)",
                        category: "USBSelection"
                    )
                }

                self.unreadableExternalUSBMediaCount = unreadableCount
                self.hasUnreadableExternalUSBMedia = unreadableCount > 0
            }
        }
    }

    func checkCapacity() {
        guard let drive = selectedDrive, let minCapacity = requiredUSBCapacityBytes else {
            isCapacitySufficient = false
            capacityCheckFinished = false
            return
        }

        if isLinuxDetected || isWindowsWorkflowSupported {
            let wholeDisk = USBDriveLogic.wholeDiskName(from: drive.device)
            if let capacity = linuxWholeDiskCapacityCache[wholeDisk] {
                withAnimation {
                    isCapacitySufficient = capacity >= Int64(minCapacity)
                    capacityCheckFinished = true
                }
            } else {
                isCapacitySufficient = false
                capacityCheckFinished = true
            }
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
