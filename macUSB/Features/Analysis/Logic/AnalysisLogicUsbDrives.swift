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

    func setMacOSCreateInstallMediaVolumeOverrideActive(_ isActive: Bool) {
        let effectiveOverride = isActive && supportsMacOSCreateInstallMediaVolumeOverride
        isMacOSCreateInstallMediaVolumeOverrideActive = effectiveOverride

        guard isMacOSUSBTargetWorkflow else { return }
        availableDrives = effectiveOverride
            ? macOSOptionUSBTargetsCache
            : physicalUSBTargetsCache
    }

    func refreshDrives() {
        let allowExternal = UserDefaults.standard.bool(forKey: "AllowExternalDrives")

        if usesPhysicalUSBTargetSelection {
            guard !isPhysicalDriveRefreshRunning else { return }

            physicalDriveRefreshGeneration &+= 1
            let refreshGeneration = physicalDriveRefreshGeneration
            let isMacOSPhysicalTargetWorkflow = isMacOSUSBTargetWorkflow
            isPhysicalDriveRefreshRunning = true

            DispatchQueue.global(qos: .utility).async { [weak self] in
                let physicalDrives: [USBDrive]
                let optionDrives: [USBDrive]
                let capacityByWholeDisk: [String: Int64]
                if isMacOSPhysicalTargetWorkflow {
                    let enumerated = USBDriveLogic.enumerateAvailableMacOSTargetSetsWithCapacities(
                        allowExternalHardDrives: allowExternal
                    )
                    physicalDrives = enumerated.physicalDrives
                    optionDrives = enumerated.optionDrives
                    capacityByWholeDisk = enumerated.capacityByWholeDisk
                } else {
                    let enumerated = USBDriveLogic.enumerateAvailablePhysicalUSBDrivesWithCapacities(
                        allowExternalHardDrives: allowExternal
                    )
                    physicalDrives = enumerated.drives
                    optionDrives = enumerated.drives
                    capacityByWholeDisk = enumerated.capacityByWholeDisk
                }

                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.physicalDriveRefreshGeneration == refreshGeneration else { return }

                    self.isPhysicalDriveRefreshRunning = false
                    guard self.usesPhysicalUSBTargetSelection,
                          self.isMacOSUSBTargetWorkflow == isMacOSPhysicalTargetWorkflow else { return }

                    self.physicalUSBTargetsCache = physicalDrives
                    self.macOSOptionUSBTargetsCache = optionDrives
                    self.wholeDiskCapacityCache = capacityByWholeDisk

                    let effectiveVolumeOverride = isMacOSPhysicalTargetWorkflow
                        && self.isMacOSCreateInstallMediaVolumeOverrideActive
                        && self.supportsMacOSCreateInstallMediaVolumeOverride
                    self.isMacOSCreateInstallMediaVolumeOverrideActive = effectiveVolumeOverride
                    let displayedDrives = effectiveVolumeOverride ? optionDrives : physicalDrives
                    let selectableDrives = isMacOSPhysicalTargetWorkflow
                        ? (physicalDrives + optionDrives)
                        : physicalDrives
                    let activeSelectionID = self.selectedDriveSelectionID ?? self.selectedDrive?.selectionID
                    let resolvedSelection = activeSelectionID.flatMap { selectionID in
                        selectableDrives.first(where: { $0.selectionID == selectionID })
                    }

                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.synchronizeDriveSelection {
                            self.availableDrives = displayedDrives
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
            physicalDriveRefreshGeneration &+= 1
            isPhysicalDriveRefreshRunning = false
            wholeDiskCapacityCache = [:]
            physicalUSBTargetsCache = []
            macOSOptionUSBTargetsCache = []
            isMacOSCreateInstallMediaVolumeOverrideActive = false
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
