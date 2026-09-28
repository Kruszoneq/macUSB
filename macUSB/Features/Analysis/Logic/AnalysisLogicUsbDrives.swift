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
                        "Unreadable USB devices detected: \(unreadableCount)",
                        category: "USBSelection"
                    )
                }

                self.unreadableExternalUSBMediaCount = unreadableCount
                self.hasUnreadableExternalUSBMedia = unreadableCount > 0
            }
        }
    }

    func checkCapacity(logResult: Bool = false) {
        guard let drive = selectedDrive else {
            isCapacitySufficient = false
            capacityCheckFinished = false
            return
        }

        guard let minCapacity = usbTargetCapacityRequirement?.minimumBytes else {
            isCapacitySufficient = false
            capacityCheckFinished = false
            if logResult {
                log("Target capacity validation for \(drive.device): capacity requirement unavailable; result=undetermined.", category: "USBSelection")
            }
            return
        }

        let capacityBytes: Int64?
        if drive.isWholeDiskTarget {
            let wholeDisk = USBDriveLogic.wholeDiskName(from: drive.device)
            capacityBytes = wholeDiskCapacityCache[wholeDisk]
        } else if let values = try? drive.url.resourceValues(forKeys: [.volumeTotalCapacityKey]),
                  let capacity = values.volumeTotalCapacity {
            capacityBytes = Int64(capacity)
        } else {
            capacityBytes = nil
        }

        let sufficient = capacityBytes.map { $0 >= minCapacity } ?? false
        withAnimation {
            isCapacitySufficient = sufficient
            capacityCheckFinished = true
        }

        if logResult {
            let kind = drive.isWholeDiskTarget ? "disk" : "volume"
            let actualCapacity = capacityBytes.map { "\($0) B" } ?? "unknown"
            let result = sufficient ? "sufficient" : "insufficient"
            let reason = capacityBytes == nil ? ", reason=capacity could not be read" : ""
            log(
                "Selected target capacity validation [\(kind) \(drive.device)]: required=\(minCapacity) B, capacity=\(actualCapacity), result=\(result)\(reason).",
                category: "USBSelection"
            )
        }
    }
}
