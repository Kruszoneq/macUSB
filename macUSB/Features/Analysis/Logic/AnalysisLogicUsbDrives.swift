import SwiftUI
import Foundation

extension AnalysisLogic {
    var isMacOSUSBTargetWorkflow: Bool {
        let hasMacOSSource = sourceAppURL != nil || isPPC || isMavericks
        let isDetected = isSystemDetected || isPPC || isMavericks
        return hasMacOSSource && isDetected && !showUnsupportedMessage && !isUnsupportedSierra
    }

    var supportsMacOSCreateInstallMediaVolumeOverride: Bool {
        isMacOSUSBTargetWorkflow
            && !isPPC
            && !isMavericks
            && !isRestoreLegacy
            && macOSArchitectureBlockReason == nil
            && createInstallMediaInspection.architecture != .notApplicable
    }

    var usesPhysicalUSBTargetSelection: Bool {
        isLinuxDetected || isWindowsWorkflowSupported || isMacOSUSBTargetWorkflow
    }

    private var requiredUSBCapacityBytes: Int? {
        guard let requiredGB = requiredUSBCapacityGB else { return nil }
        switch requiredGB {
        case 1:
            return 900_000_000
        case 2:
            return 1_800_000_000
        case 4:
            return 3_600_000_000
        case 8:
            return 7_300_000_000
        case 16:
            return 14_700_000_000
        case 32:
            return 29_400_000_000
        case 64:
            return 58_800_000_000
        default:
            return requiredGB * 1_000_000_000
        }
    }

    func refreshDrives(useMacOSCreateInstallMediaVolumeOverride: Bool = false) {
        let allowExternal = UserDefaults.standard.bool(forKey: "AllowExternalDrives")

        if usesPhysicalUSBTargetSelection {
            let effectiveVolumeOverride = useMacOSCreateInstallMediaVolumeOverride
                && supportsMacOSCreateInstallMediaVolumeOverride

            if isPhysicalDriveRefreshRunning,
               activePhysicalDriveRefreshUsesVolumeOverride == effectiveVolumeOverride {
                return
            }

            physicalDriveRefreshGeneration &+= 1
            let refreshGeneration = physicalDriveRefreshGeneration
            let isMacOSPhysicalTargetWorkflow = isMacOSUSBTargetWorkflow
            isPhysicalDriveRefreshRunning = true
            activePhysicalDriveRefreshUsesVolumeOverride = effectiveVolumeOverride

            DispatchQueue.global(qos: .utility).async { [weak self] in
                let enumerated: (drives: [USBDrive], capacityByWholeDisk: [String: Int64])
                if isMacOSPhysicalTargetWorkflow {
                    enumerated = USBDriveLogic.enumerateAvailableMacOSTargetsWithCapacities(
                        allowExternalHardDrives: allowExternal,
                        useCreateInstallMediaVolumeOverride: effectiveVolumeOverride
                    )
                } else {
                    enumerated = USBDriveLogic.enumerateAvailablePhysicalUSBDrivesWithCapacities(
                        allowExternalHardDrives: allowExternal
                    )
                }

                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.physicalDriveRefreshGeneration == refreshGeneration,
                          self.activePhysicalDriveRefreshUsesVolumeOverride == effectiveVolumeOverride else {
                        return
                    }

                    self.isPhysicalDriveRefreshRunning = false
                    self.activePhysicalDriveRefreshUsesVolumeOverride = nil

                    guard self.usesPhysicalUSBTargetSelection else { return }
                    if effectiveVolumeOverride {
                        guard self.supportsMacOSCreateInstallMediaVolumeOverride else { return }
                    }

                    self.wholeDiskCapacityCache = enumerated.capacityByWholeDisk
                    let activeSelectionID = self.selectedDriveSelectionID ?? self.selectedDrive?.selectionID
                    let resolvedSelection = activeSelectionID.flatMap { selectionID in
                        enumerated.drives.first(where: { $0.selectionID == selectionID })
                    }
                    let preservedSelectionID = effectiveVolumeOverride && resolvedSelection == nil
                        ? activeSelectionID
                        : resolvedSelection?.selectionID

                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.synchronizeDriveSelection {
                            self.availableDrives = enumerated.drives
                            self.selectedDrive = resolvedSelection
                            self.selectedDriveSelectionID = preservedSelectionID
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
            physicalDriveRefreshGeneration &+= 1
            isPhysicalDriveRefreshRunning = false
            activePhysicalDriveRefreshUsesVolumeOverride = nil
            wholeDiskCapacityCache = [:]
        }

        let currentSelectedSelectionID = selectedDriveSelectionID ?? selectedDrive?.selectionID
        let foundDrives = USBDriveLogic.enumerateAvailableVolumeDrives(
            allowExternalHardDrives: allowExternal
        )

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

        if drive.isWholeDiskTarget {
            let wholeDisk = USBDriveLogic.wholeDiskName(from: drive.device)
            if let capacity = wholeDiskCapacityCache[wholeDisk] {
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
