import SwiftUI
import AppKit

struct AnalysisUSBDiscoveryNotice: Equatable {
    let titleKey: String
    let descriptionKey: String
    let offersVerifiedAlternative: Bool
    let waiting: Bool
}

extension AnalysisLogic {
    var usbDiscoveryNotice: AnalysisUSBDiscoveryNotice? {
        // The availability card occupies the destructive-warning position.
        // Never repeat this selected-target problem above the same selector.
        if isUSBAvailabilityConfirmationExpired { return nil }
        let alternative = usbDiscoveryState.hasCurrentSnapshot && selectableUSBTargets.contains { drive in
            guard let required = usbTargetCapacityRequirement?.minimumBytes,
                  let proof = usbDiscoveryState.snapshot?.verification[drive.selectionID], proof.problem == nil, proof.isFresh(),
                  case .success(let actual) = proof.capacity else { return false }
            return actual >= required
        }
        if let failure = usbDiscoveryState.failure {
            return AnalysisUSBDiscoveryNotice(titleKey: "analysis.usb.discovery.refresh.title", descriptionKey: usbSelectionProblemDescriptionKey(failure), offersVerifiedAlternative: false, waiting: false)
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

    private func usbSelectionProblemDescriptionKey(_ problem: USBDiscoveryProblem) -> String {
        if usbDiscoveryState.failure != nil, case .query(.exitStatus) = problem {
            return "analysis.usb.discovery.refresh.description"
        }
        return problem.descriptionKey
    }

    var isUSBAvailabilityConfirmationExpired: Bool {
        selectedDrive != nil && usbTargetReadiness.problem == .confirmationExpired
    }

    var canRetryUSBDiscovery: Bool {
        usbDiscoveryState.activity != .checking && usbDiscoveryState.activity != .waiting
    }

    /// The setter of the picker binding is the deliberate-selection boundary.
    /// Automatic snapshot application never calls this alert path.
    func selectUSBTarget(_ selectionID: String?) {
        withAnimation(.easeInOut(duration: 0.24)) {
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
        alert.informativeText = String(localized: String.LocalizationValue(usbSelectionProblemDescriptionKey(problem)), table: "Analysis")
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

    var body: some View {
        StatusCard(tone: notice.waiting ? .subtle : .warning, density: .compact) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: notice.waiting ? "hourglass.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(notice.waiting ? Color.secondary : Color.orange)
                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedStringKey(notice.titleKey), tableName: "Analysis").font(.headline)
                    Text(LocalizedStringKey(notice.descriptionKey), tableName: "Analysis").font(.subheadline)
                    if logic.usbDiscoveryState.activity == .waiting && !notice.waiting {
                        Text("analysis.usb.discovery.waiting.description", tableName: "Analysis").font(.subheadline)
                    }
                    if notice.offersVerifiedAlternative {
                        Text("analysis.usb.discovery.partial.alternative", tableName: "Analysis").font(.subheadline)
                    }
                    Button { logic.retryUSBDiscovery() } label: {
                        Text("analysis.usb.discovery.retry.action", tableName: "Analysis")
                    }
                    .macUSBSecondaryButtonStyle()
                    .disabled(!logic.canRetryUSBDiscovery)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
