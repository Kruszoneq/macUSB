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

    var requiresWholeDiskMacOSTarget: Bool {
        isPPC || isRestoreLegacy || isMavericks
    }

    var selectableUSBTargets: [USBDrive] {
        supportsMacOSCreateInstallMediaVolumeOverride
            ? macOSOptionUSBTargetsCache
            : physicalUSBTargetsCache
    }

    private var currentlyPresentedUSBTargets: [USBDrive] {
        isMacOSCreateInstallMediaVolumeOverrideActive
            && supportsMacOSCreateInstallMediaVolumeOverride
            ? macOSOptionUSBTargetsCache
            : physicalUSBTargetsCache
    }

    private func applyCurrentUSBTargetPresentation() {
        presentedUSBTargets = currentlyPresentedUSBTargets
    }

    private func normalizeSelectionForCurrentTargetCatalogIfNeeded() {
        guard hasPreparedUSBTargetSnapshot,
              let selectedDrive,
              !selectableUSBTargets.contains(where: { $0.selectionID == selectedDrive.selectionID }) else {
            return
        }

        let selectedWholeDisk = USBDriveLogic.wholeDiskName(from: selectedDrive.device)
        let normalizedSelection = physicalUSBTargetsCache.first(where: { $0.device == selectedWholeDisk })
        synchronizeDriveSelection {
            self.selectedDrive = normalizedSelection
            self.selectedDriveSelectionID = normalizedSelection?.selectionID
        }
        if normalizedSelection == nil {
            capacityCheckFinished = false
        }
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
        applyCurrentUSBTargetPresentation()
        normalizeSelectionForCurrentTargetCatalogIfNeeded()
    }

    func refreshDrives() {
        let allowExternal = UserDefaults.standard.bool(forKey: "AllowExternalDrives")
        guard !isPhysicalDriveRefreshRunning else { return }

        physicalDriveRefreshGeneration &+= 1
        let refreshGeneration = physicalDriveRefreshGeneration
        isPhysicalDriveRefreshRunning = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let enumerated = USBDriveLogic.enumerateAvailableMacOSTargetSetsWithCapacities(
                allowExternalHardDrives: allowExternal
            )

            DispatchQueue.main.async {
                guard let self else { return }
                guard self.physicalDriveRefreshGeneration == refreshGeneration else { return }

                self.isPhysicalDriveRefreshRunning = false
                self.physicalUSBTargetsCache = enumerated.physicalDrives
                self.macOSOptionUSBTargetsCache = enumerated.optionDrives
                self.wholeDiskCapacityCache = enumerated.capacityByWholeDisk
                self.hasPreparedUSBTargetSnapshot = true

                let effectiveVolumeOverride = self.isMacOSCreateInstallMediaVolumeOverrideActive
                    && self.supportsMacOSCreateInstallMediaVolumeOverride
                self.isMacOSCreateInstallMediaVolumeOverrideActive = effectiveVolumeOverride

                let allowsVolumeSelection = self.supportsMacOSCreateInstallMediaVolumeOverride
                let selectableDrives = allowsVolumeSelection
                    ? enumerated.optionDrives
                    : enumerated.physicalDrives
                let activeSelectionID = self.selectedDriveSelectionID ?? self.selectedDrive?.selectionID
                var resolvedSelection = activeSelectionID.flatMap { selectionID in
                    selectableDrives.first(where: { $0.selectionID == selectionID })
                }
                if resolvedSelection == nil,
                   !allowsVolumeSelection,
                   let previousSelection = self.selectedDrive {
                    let selectedWholeDisk = USBDriveLogic.wholeDiskName(from: previousSelection.device)
                    resolvedSelection = enumerated.physicalDrives.first(where: { $0.device == selectedWholeDisk })
                }

                self.synchronizeDriveSelection {
                    self.applyCurrentUSBTargetPresentation()
                    self.selectedDrive = resolvedSelection
                    self.selectedDriveSelectionID = resolvedSelection?.selectionID
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
