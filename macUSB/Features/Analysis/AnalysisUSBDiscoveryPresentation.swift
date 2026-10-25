import SwiftUI
import AppKit

struct AnalysisUSBDiscoveryNotice: Equatable {
    let titleKey: String
    let descriptionKey: String
    let offersVerifiedAlternative: Bool
    let waiting: Bool
}

/// A lifecycle pause changes admission, not the last result shown to the user.
struct AnalysisUSBHeldPresentation {
    let discovery: AnalysisUSBDiscoveryState
    let readiness: USBTargetReadiness
    let selectionID: String?
    let identity: String?
    let requiredBytes: Int64?
    let allowExternalDrives: Bool
    let capturedAt: TimeInterval
    var resumedAt: TimeInterval?
}

extension AnalysisLogic {
    private var currentHeldUSBPresentation: AnalysisUSBHeldPresentation? {
        guard let held = heldUSBDiscoveryPresentation,
              held.selectionID == selectedDrive?.selectionID,
              held.identity == selectedTargetIdentity,
              held.requiredBytes == usbTargetCapacityRequirement?.minimumBytes,
              held.allowExternalDrives == UserDefaults.standard.bool(forKey: "AllowExternalDrives") else { return nil }
        return held
    }

    var usbDiscoveryPresentationState: AnalysisUSBDiscoveryState {
        currentHeldUSBPresentation?.discovery ?? usbDiscoveryState
    }

    var usbTargetPresentationReadiness: USBTargetReadiness {
        currentHeldUSBPresentation?.readiness ?? usbTargetReadiness
    }

    var shouldShowMacOSVolumeSelectionHint: Bool {
        guard supportsMacOSCreateInstallMediaVolumeOverride, !isAnalyzing,
              usbDiscoveryPresentationState.hasCurrentSnapshot,
              let snapshot = usbDiscoveryPresentationState.snapshot,
              snapshot.allowExternalDrives == UserDefaults.standard.bool(forKey: "AllowExternalDrives") else { return false }
        return snapshot.optionDrives.contains { drive in
            guard !drive.isWholeDiskTarget,
                  let proof = snapshot.verification[drive.selectionID] else { return false }
            return proof.problem == nil
        }
    }

    func holdUSBDiscoveryPresentation() {
        let previous = currentHeldUSBPresentation
        heldUSBDiscoveryPresentation = AnalysisUSBHeldPresentation(
            discovery: previous?.discovery ?? usbDiscoveryState,
            readiness: previous?.readiness ?? usbTargetReadiness,
            selectionID: selectedDrive?.selectionID, identity: selectedTargetIdentity,
            requiredBytes: usbTargetCapacityRequirement?.minimumBytes,
            allowExternalDrives: UserDefaults.standard.bool(forKey: "AllowExternalDrives"),
            capturedAt: previous?.capturedAt ?? ProcessInfo.processInfo.systemUptime
        )
    }

    func resumeUSBDiscoveryPresentation() {
        guard heldUSBDiscoveryPresentation != nil else { return }
        guard var held = currentHeldUSBPresentation else {
            heldUSBDiscoveryPresentation = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let resumedAt = held.resumedAt {
            // Bound the presentation grace as well: a stalled active refresh
            // must eventually surface loss of confirmation. Admission never
            // uses this grace or renews the evidence timestamp.
            if now - resumedAt >= USBTargetVerification.maximumConfirmationAge {
                heldUSBDiscoveryPresentation = nil
            }
        } else {
            held.resumedAt = now
            heldUSBDiscoveryPresentation = held
        }
    }

    var usbDiscoveryNotice: AnalysisUSBDiscoveryNotice? {
        // The availability card accompanies the persistent destructive warning.
        // Never repeat this selected-target problem above the same selector.
        if isUSBAvailabilityConfirmationExpired { return nil }
        let usbDiscoveryState = usbDiscoveryPresentationState
        let usbTargetReadiness = usbTargetPresentationReadiness
        let verificationTime = currentHeldUSBPresentation?.capturedAt ?? ProcessInfo.processInfo.systemUptime
        let alternative = usbDiscoveryState.hasCurrentSnapshot && selectableUSBTargets.contains { drive in
            guard let required = usbTargetCapacityRequirement?.minimumBytes,
                  let proof = usbDiscoveryState.snapshot?.verification[drive.selectionID], proof.problem == nil, proof.isFresh(at: verificationTime),
                  case .success(let actual) = proof.capacity else { return false }
            return actual >= required
        }
        if let failure = usbDiscoveryState.failure {
            return AnalysisUSBDiscoveryNotice(titleKey: "analysis.usb.discovery.refresh.title", descriptionKey: usbSelectionProblemDescriptionKey(failure, enumerationFailed: true), offersVerifiedAlternative: false, waiting: false)
        }
        if usbTargetReadiness.problem == .targetMissing,
           usbDiscoveryState.hasCurrentSnapshot, selectableUSBTargets.isEmpty,
           usbDiscoveryState.snapshot?.issues.isEmpty == true { return nil }
        if let problem = usbTargetReadiness.problem, problem != .query(.cancelled), problem != .query(.busy) {
            return AnalysisUSBDiscoveryNotice(titleKey: "analysis.usb.discovery.unavailable.title", descriptionKey: problem.descriptionKey, offersVerifiedAlternative: alternative, waiting: false)
        }
        if usbDiscoveryState.activity == .waiting && selectedDrive == nil {
            return AnalysisUSBDiscoveryNotice(titleKey: "analysis.usb.discovery.waiting.title", descriptionKey: "analysis.usb.discovery.waiting.description", offersVerifiedAlternative: false, waiting: true)
        }
        if usbDiscoveryState.hasCurrentSnapshot, let issues = usbDiscoveryState.snapshot?.issues, !issues.isEmpty {
            return AnalysisUSBDiscoveryNotice(titleKey: "analysis.usb.discovery.partial.title", descriptionKey: "analysis.usb.discovery.partial.description", offersVerifiedAlternative: alternative, waiting: false)
        }
        return nil
    }

    private func usbSelectionProblemDescriptionKey(_ problem: USBDiscoveryProblem, enumerationFailed: Bool) -> String {
        if enumerationFailed, case .query(.exitStatus) = problem {
            return "analysis.usb.discovery.refresh.description"
        }
        return problem.descriptionKey
    }

    var isUSBAvailabilityConfirmationExpired: Bool {
        selectedDrive != nil && usbTargetPresentationReadiness.problem == .confirmationExpired
    }

    /// The setter of the picker binding is the deliberate-selection boundary.
    /// Automatic snapshot application never calls this alert path.
    func selectUSBTarget(_ selectionID: String?) {
        withAnimation(.easeInOut(duration: 0.24)) {
            heldUSBDiscoveryPresentation = nil
            if selectionID == nil { usbTargetReadiness = .noSelection }
            selectedDriveSelectionID = selectionID
            checkCapacity()
        }
        guard let problem = usbTargetReadiness.problem,
              problem != .query(.busy), problem != .query(.cancelled), problem != .confirmationExpired,
              !isUSBSelectionAlertPresented else { return }
        isUSBSelectionAlertPresented = true
        log("User attempted unavailable USB target selection: device=\(selectedDrive?.device ?? "none"), reason=\(problem).", category: "USBSelection")
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "analysis.usb.discovery.unavailable.title", table: "Analysis")
        alert.informativeText = String(localized: String.LocalizationValue(usbSelectionProblemDescriptionKey(problem, enumerationFailed: usbDiscoveryState.failure != nil)), table: "Analysis")
        alert.addButton(withTitle: String(localized: "analysis.usb.discovery.retry.action", table: "Analysis"))
        alert.addButton(withTitle: String(localized: "analysis.usb.discovery.close.action", table: "Analysis"))
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isUSBSelectionAlertPresented = false
            if response == .alertFirstButtonReturn { self.retryUSBDiscovery() }
        }
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }
}

struct AnalysisUSBDiscoveryNoticeView: View {
    @ObservedObject var logic: AnalysisLogic
    let notice: AnalysisUSBDiscoveryNotice
    let sectionIconFont: Font

    var body: some View {
        StatusCard(tone: notice.waiting ? .subtle : .warning, density: .compact) {
            HStack(alignment: .center) {
                Image(systemName: notice.waiting ? "hourglass.circle" : "exclamationmark.triangle.fill")
                    .font(sectionIconFont)
                    .foregroundStyle(notice.waiting ? Color.secondary : Color.orange)
                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                VStack(alignment: .leading) {
                    Text(LocalizedStringKey(notice.titleKey), tableName: "Analysis")
                        .font(.headline)
                        .foregroundColor(notice.waiting ? .primary : .orange)
                    Text(LocalizedStringKey(notice.descriptionKey), tableName: "Analysis")
                        .font(.subheadline)
                        .foregroundColor(notice.waiting ? .secondary : .orange.opacity(0.8))
                    if logic.usbDiscoveryPresentationState.activity == .waiting && !notice.waiting {
                        Text("analysis.usb.discovery.waiting.description", tableName: "Analysis")
                            .font(.subheadline)
                            .foregroundColor(.orange.opacity(0.8))
                    }
                    if notice.offersVerifiedAlternative {
                        Text("analysis.usb.discovery.partial.alternative", tableName: "Analysis")
                            .font(.subheadline)
                            .foregroundColor(notice.waiting ? .secondary : .orange.opacity(0.8))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
