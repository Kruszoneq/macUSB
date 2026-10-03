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
            && !isPPC && !isMavericks && !isRestoreLegacy
            && macOSArchitectureBlockReason == nil
            && createInstallMediaInspection.architecture != .notApplicable
    }

    var requiresWholeDiskMacOSTarget: Bool { isPPC || isRestoreLegacy || isMavericks }

    var selectableUSBTargets: [USBDrive] {
        supportsMacOSCreateInstallMediaVolumeOverride ? macOSOptionUSBTargetsCache : physicalUSBTargetsCache
    }

    private func applyCurrentUSBTargetPresentation() {
        presentedUSBTargets = isMacOSCreateInstallMediaVolumeOverrideActive && supportsMacOSCreateInstallMediaVolumeOverride
            ? macOSOptionUSBTargetsCache : physicalUSBTargetsCache
    }

    func resolveUSBSelection(_ selectionID: String?) {
        selectedDrive = selectionID.flatMap { id in selectableUSBTargets.first { $0.selectionID == id } }
    }

    private func normalizeSelectionForCurrentTargetCatalogIfNeeded() {
        guard hasPreparedUSBTargetSnapshot, let selectedDrive,
              !selectableUSBTargets.contains(where: { $0.selectionID == selectedDrive.selectionID }) else { return }
        // Only workflow routing can normalize a volume to its own physical parent.
        let parent = physicalUSBTargetsCache.first { $0.device == USBDriveLogic.wholeDiskName(from: selectedDrive.device) }
        synchronizeDriveSelection {
            self.selectedDrive = parent
            self.selectedDriveSelectionID = parent?.selectionID
            self.selectedTargetIdentity = self.selectedTargetIdentity?.components(separatedBy: ":").first
        }
        checkCapacity()
    }

    func setMacOSCreateInstallMediaVolumeOverrideActive(_ isActive: Bool) {
        withAnimation(.easeInOut(duration: 0.24)) {
            isMacOSCreateInstallMediaVolumeOverrideActive = isActive && supportsMacOSCreateInstallMediaVolumeOverride
            applyCurrentUSBTargetPresentation()
            normalizeSelectionForCurrentTargetCatalogIfNeeded()
        }
    }

    func setDriveRefreshVisible(_ visible: Bool) {
        isDriveRefreshVisible = visible
        if visible { refreshDrives(force: true, reason: "analysis screen visible") }
        else { cancelDriveRefresh(reason: "analysis screen hidden") }
    }

    func cancelDriveRefresh(reason: String = "application inactive") {
        physicalDriveRefreshGeneration &+= 1
        driveRefreshCancellation?.cancel()
        // The registry read itself cannot be interrupted. Retain ownership
        // until its callback returns, but revoke permission to navigate.
        usbDiscoveryState.admissionRequest?.isCancelled = true
        usbDiscoveryState.activity = .suspended
        usbDiscoveryState.outcome = .pending
        setUSBReadiness(selectedDrive == nil ? .noSelection : .unverified(.query(.cancelled)))
        log("USB discovery cancelled: generation=\(physicalDriveRefreshGeneration), reason=\(reason), ownerRunning=\(driveRefreshPolicy.isRunning).", category: "USBSelection")
    }

    func usbExternalDrivePreferenceChanged() {
        log("USB discovery preference changed: AllowExternalDrives=\(UserDefaults.standard.bool(forKey: "AllowExternalDrives")).", category: "USBSelection")
        cancelDriveRefresh(reason: "external-drive preference changed")
        refreshDrives(force: true, reason: "external-drive preference changed")
    }

    func retryUSBDiscovery() {
        log("USB discovery manually retried.", category: "USBSelection")
        refreshDrives(force: true, reason: "user retry")
    }

    func refreshDrives(force: Bool = false, reason: String = "periodic or workflow refresh") {
        guard isDriveRefreshVisible, NSApp.isActive else { return }
        // Evaluate evidence on every existing UI tick, even while a worker or
        // an unreaped child prevents another scan from starting.
        withAnimation(.easeInOut(duration: 0.24)) { checkCapacity() }
        guard !driveRefreshPolicy.isRunning else { return }
        // The worker may have returned after bounded cleanup while its child
        // still owns the process slot. Never queue another scan behind it.
        if USBDiscoveryProcessRunner.shared.isOccupied {
            usbDiscoveryState.activity = .waiting
            usbDiscoveryDiagnostics.record("USB discovery waiting: generation=\(physicalDriveRefreshGeneration), reason=\(reason), subprocess slot still occupied.", key: "slot", signature: "busy", workflow: selectedWorkflowForLogging)
            return
        }
        usbDiscoveryDiagnostics.recover("USB discovery resumed: subprocess slot available.", key: "slot", workflow: selectedWorkflowForLogging)
        guard driveRefreshPolicy.begin(at: ProcessInfo.processInfo.systemUptime, visible: true, active: true, force: force) else { return }
        let allowExternal = UserDefaults.standard.bool(forKey: "AllowExternalDrives")
        physicalDriveRefreshGeneration &+= 1
        let generation = physicalDriveRefreshGeneration
        let cancellation = USBDiscoveryCancellation()
        driveRefreshCancellation = cancellation
        usbDiscoveryState.activity = .checking
        let workflow = selectedWorkflowForLogging
        let diagnostics = usbDiscoveryDiagnostics
        if reason == "user retry" { diagnostics.record("USB scan started: generation=\(generation), reason=\(reason), AllowExternalDrives=\(allowExternal).", key: "scan.start", signature: "\(reason):\(allowExternal)", workflow: workflow, force: true) }
        let startedAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = USBTargetDiscoveryService.scan(allowExternalDrives: allowExternal, cancellation: cancellation, scanID: generation, workflow: workflow, diagnostics: diagnostics, manualRetry: reason == "user retry")
            DispatchQueue.main.async {
                guard let self else { return }
                self.driveRefreshPolicy.finish()
                self.driveRefreshCancellation = nil
                guard self.physicalDriveRefreshGeneration == generation,
                      allowExternal == UserDefaults.standard.bool(forKey: "AllowExternalDrives") else {
                    self.log("USB scan result discarded: stale generation=\(generation), current=\(self.physicalDriveRefreshGeneration), reason=cancellation or preference change.", category: "USBSelection")
                    self.refreshDrives(force: true, reason: "resume after stale scan")
                    return
                }
                let elapsed = String(format: "%.3f", ProcessInfo.processInfo.systemUptime - startedAt)
                withAnimation(.easeInOut(duration: 0.24)) {
                    self.usbDiscoveryState.activity = .idle
                    switch result {
                    case .complete(let snapshot), .partial(let snapshot):
                        let presentation = self.retainingUnresolvedUSBSelection(in: self.retainingUSBConfirmationTimes(in: snapshot))
                        self.usbDiscoveryState.snapshot = presentation
                        self.usbDiscoveryState.outcome = .current
                        self.applyUSBDiscoverySnapshot(presentation)
                        if snapshot.issues.contains(where: { $0.problem == .query(.busy) }) { self.usbDiscoveryState.activity = .waiting }
                        diagnostics.recordSnapshot(snapshot, message: "USB scan completed: generation=\(generation), duration=\(elapsed)s, physicalTargets=\(snapshot.physicalDrives.count), optionTargets=\(snapshot.optionDrives.count), issues=\(snapshot.issues).", workflow: workflow, force: reason == "user retry")
                    case .failed(let problem):
                        self.usbDiscoveryState.outcome = .failed(problem)
                        self.checkCapacity()
                        diagnostics.record("USB scan failed: generation=\(generation), duration=\(elapsed)s, reason=\(problem).", key: "scan.result", signature: "\(problem)", workflow: workflow)
                    case .busy:
                        self.usbDiscoveryState.activity = .waiting
                        diagnostics.record("USB scan waiting: generation=\(generation), duration=\(elapsed)s, reason=runner busy.", key: "scan.result", signature: "busy", workflow: workflow)
                    case .cancelled:
                        self.usbDiscoveryState.activity = .suspended
                        self.usbDiscoveryState.outcome = .pending
                        self.checkCapacity()
                        self.log("USB scan cancelled normally: generation=\(generation), duration=\(elapsed)s.", category: "USBSelection")
                    }
                }
            }
        }
    }

    private func retainingUSBConfirmationTimes(in snapshot: USBDiscoverySnapshot) -> USBDiscoverySnapshot {
        guard usbDiscoveryState.snapshot?.allowExternalDrives == snapshot.allowExternalDrives else { return snapshot }
        var verification = snapshot.verification
        for (id, var proof) in verification where proof.confirmedAt == nil {
            guard let previous = usbDiscoveryState.snapshot?.verification[id],
                  previous.identity == proof.identity,
                  proof.problem != .identityChanged, proof.problem != .targetMissing else { continue }
            // Preserve the age of the last successful read during uncertainty,
            // without restoring its capacity or authorizing failed evidence.
            proof.confirmedAt = previous.confirmedAt
            verification[id] = proof
        }
        return USBDiscoverySnapshot(physicalDrives: snapshot.physicalDrives, optionDrives: snapshot.optionDrives,
            verification: verification, issues: snapshot.issues, allowExternalDrives: snapshot.allowExternalDrives)
    }

    private func retainingUnresolvedUSBSelection(in snapshot: USBDiscoverySnapshot) -> USBDiscoverySnapshot {
        guard let selected = selectedDrive,
              !snapshot.optionDrives.contains(where: { $0.selectionID == selected.selectionID }),
              let issue = snapshot.issues.first(where: {
                  $0.device == selected.device || $0.device == USBDriveLogic.wholeDiskName(from: selected.device)
                      || (!selected.isWholeDiskTarget && $0.device == "mounted volumes")
              }) else { return snapshot }
        // A read error is not proof of removal. Retain the selected row with
        // explicitly failed evidence; never authorize it from the old cache.
        var physical = snapshot.physicalDrives
        var option = snapshot.optionDrives
        if selected.isWholeDiskTarget { physical.append(selected) }
        option.append(selected)
        physical.sort { $0.device.localizedStandardCompare($1.device) == .orderedAscending }
        option.sort { $0.device.localizedStandardCompare($1.device) == .orderedAscending }
        var verification = snapshot.verification
        verification[selected.selectionID] = USBTargetVerification(identity: selectedTargetIdentity, capacity: .failure(issue.problem), confirmedAt: usbDiscoveryState.snapshot?.verification[selected.selectionID]?.confirmedAt)
        return USBDiscoverySnapshot(physicalDrives: physical, optionDrives: option, verification: verification, issues: snapshot.issues, allowExternalDrives: snapshot.allowExternalDrives)
    }

    private func applyUSBDiscoverySnapshot(_ snapshot: USBDiscoverySnapshot) {
        let previous = selectedDrive
        let id = selectedDriveSelectionID ?? previous?.selectionID
        var resolved = id.flatMap { id in selectableUSBTargets.first { $0.selectionID == id } }
        if resolved == nil, requiresWholeDiskMacOSTarget, let previous, !previous.isWholeDiskTarget {
            resolved = snapshot.physicalDrives.first { $0.device == USBDriveLogic.wholeDiskName(from: previous.device) }
            selectedTargetIdentity = selectedTargetIdentity?.components(separatedBy: ":").first
        }
        synchronizeDriveSelection {
            applyCurrentUSBTargetPresentation()
            selectedDrive = resolved
            selectedDriveSelectionID = resolved?.selectionID
        }
        if previous != nil, resolved == nil {
            let previousDevice = previous!.device
            let parentDevice = USBDriveLogic.wholeDiskName(from: previousDevice)
            let problem = snapshot.physicalDrives.first { $0.device == parentDevice }
                .flatMap { snapshot.verification[$0.selectionID]?.problem }
                ?? snapshot.issues.first { $0.device == previousDevice || $0.device == parentDevice }?.problem
            setUSBReadiness(.unverified(problem ?? .targetMissing))
        } else { checkCapacity() }
    }

    func checkCapacity(logResult: Bool = false) {
        guard let drive = selectedDrive else {
            // Keep the explanation after an automatically removed target until
            // a deliberate selection or a source reset clears it.
            if usbTargetReadiness.problem == nil { setUSBReadiness(.noSelection) }
            return
        }
        if let snapshot = usbDiscoveryState.snapshot,
           snapshot.allowExternalDrives == UserDefaults.standard.bool(forKey: "AllowExternalDrives"),
           let proof = snapshot.verification[drive.selectionID],
           proof.identity == selectedTargetIdentity,
           proof.problem != .identityChanged, proof.problem != .targetMissing,
           proof.isConfirmationExpired() {
            setUSBReadiness(.unverified(.confirmationExpired), logResult: logResult); return
        }
        guard usbDiscoveryState.hasCurrentSnapshot,
              usbDiscoveryState.snapshot?.allowExternalDrives == UserDefaults.standard.bool(forKey: "AllowExternalDrives") else {
            setUSBReadiness(.unverified(usbDiscoveryState.failure ?? .query(.cancelled)), logResult: logResult)
            return
        }
        guard let verification = usbDiscoveryState.snapshot?.verification[drive.selectionID] else {
            setUSBReadiness(.unverified(.targetMissing), logResult: logResult); return
        }
        if let problem = verification.problem {
            setUSBReadiness(.unverified(problem), logResult: logResult); return
        }
        guard selectedTargetIdentity == verification.identity else {
            setUSBReadiness(.unverified(.identityChanged), logResult: logResult); return
        }
        guard verification.isFresh() else {
            setUSBReadiness(.unverified(.confirmationExpired), logResult: logResult); return
        }
        guard let required = usbTargetCapacityRequirement?.minimumBytes else {
            setUSBReadiness(.awaitingRequirement, logResult: logResult); return
        }
        switch verification.capacity {
        case .success(let actual):
            setUSBReadiness(actual >= required ? .ready(required: required, actual: actual) : .insufficient(required: required, actual: actual), logResult: logResult)
        case .failure(let problem): setUSBReadiness(.unverified(problem), logResult: logResult)
        }
    }

    private func setUSBReadiness(_ readiness: USBTargetReadiness, logResult: Bool = false) {
        let previous = usbTargetReadiness
        guard previous != readiness || logResult else { return }
        if previous != readiness { usbTargetReadiness = readiness }
        log("Selected USB target readiness: generation=\(physicalDriveRefreshGeneration), device=\(selectedDrive?.device ?? "none"), previous=\(previous), result=\(readiness), required=\(usbTargetCapacityRequirement?.minimumBytes.description ?? "unknown") B; readiness \(readiness.isReady ? "available" : "blocked").", category: "USBSelection")
    }
}
