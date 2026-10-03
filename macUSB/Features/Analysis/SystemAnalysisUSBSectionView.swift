import SwiftUI

struct SystemAnalysisUSBSectionView: View {
    @ObservedObject var logic: AnalysisLogic
    let sectionIconFont: Font
    let isSelectionEnabled: Bool

    private var shouldShowWaitingForSystemDetectionCard: Bool {
        let isUSBConnected = !logic.presentedUSBTargets.isEmpty
        let isAwaitingSystemRecognition = logic.recognizedVersion.isEmpty || logic.isAnalyzing
        let isPreparingInitialTargetSnapshot = !logic.hasPreparedUSBTargetSnapshot
        return (isUSBConnected || isPreparingInitialTargetSnapshot)
            && isAwaitingSystemRecognition
            && !isSelectionEnabled
            && logic.usbDiscoveryNotice == nil
    }

    private func pickerDisplayName(for drive: USBDrive) -> String {
        if logic.usbDiscoveryState.failure != nil || logic.usbDiscoveryState.snapshot?.verification[drive.selectionID]?.problem != nil {
            return "\(drive.device) - " + String(localized: "analysis.usb.discovery.unavailable.label", table: "Analysis")
        }
        guard drive.isWholeDiskTarget else { return drive.displayName }
        let speedText = drive.usbSpeed?.rawValue ?? "USB"
        return "\(drive.device) - \(drive.size) - \(speedText)"
    }

    private var preservedPickerSelection: USBDrive? {
        guard let selectedDrive = logic.selectedDrive,
              logic.selectableUSBTargets.contains(where: { $0.selectionID == selectedDrive.selectionID }),
              !logic.presentedUSBTargets.contains(where: { $0.selectionID == selectedDrive.selectionID }) else {
            return nil
        }
        return selectedDrive
    }

    private var needsExplicitReselectionAction: Bool {
        guard let problem = logic.usbTargetReadiness.problem, logic.selectedDrive != nil else { return false }
        return problem != .query(.busy) && problem != .query(.cancelled) && problem != .confirmationExpired
    }

    /// A failed selection must remain actionable even if the user chooses the
    /// same value again. Picker change notifications do not guarantee that.
    /// The explicit menu occupies the same selector only during an error;
    /// recovery restores the standard Picker.
    private var unavailableSelectionMenu: some View {
        Menu {
            Button { logic.selectUSBTarget(nil) } label: {
                Text("analysis.usb.target.placeholder", tableName: "Analysis")
            }
            if let preservedPickerSelection {
                Button { logic.selectUSBTarget(preservedPickerSelection.selectionID) } label: {
                    Text(verbatim: pickerDisplayName(for: preservedPickerSelection))
                }
            }
            ForEach(logic.presentedUSBTargets) { drive in
                Button { logic.selectUSBTarget(drive.selectionID) } label: {
                    Text(verbatim: pickerDisplayName(for: drive))
                }
            }
        } label: {
            Text(verbatim: logic.selectedDrive.map { pickerDisplayName(for: $0) } ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderedButton)
    }

    private func sectionDivider(_ title: LocalizedStringResource) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
            sectionDivider(LocalizedStringResource("analysis.usb.section.title", table: "Analysis"))
            StatusCard(tone: .neutral, density: .compact) {
                HStack(alignment: .top) {
                    Image(systemName: "externaldrive.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("analysis.usb.requirements.title", tableName: "Analysis").font(.headline)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                String(
                                    format: String(localized: "analysis.usb.requirements.capacity", table: "Analysis"),
                                    logic.requiredUSBCapacityDisplayValue
                                )
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            Text("analysis.usb.requirements.speed", tableName: "Analysis").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if shouldShowWaitingForSystemDetectionCard {
                    StatusCard(tone: .subtle, density: .compact) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "hourglass.circle")
                                .font(sectionIconFont)
                                .foregroundColor(.secondary)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "analysis.usb.waiting_for_system_detection.title", table: "Analysis"))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(String(localized: "analysis.usb.waiting_for_system_detection.description", table: "Analysis"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                    }
                } else {
                    Text("analysis.usb.target.label", tableName: "Analysis").font(.subheadline)
                    if !logic.hasPreparedUSBTargetSnapshot && logic.usbDiscoveryNotice == nil {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if logic.presentedUSBTargets.isEmpty && logic.usbDiscoveryState.hasCurrentSnapshot && logic.usbDiscoveryState.snapshot?.issues.isEmpty == true {
                        StatusCard(tone: .error, density: .compact) {
                            HStack {
                                Image(systemName: "externaldrive.badge.xmark").font(sectionIconFont).foregroundColor(.red).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading) {
                                    Text("analysis.usb.missing.title", tableName: "Analysis").font(.headline).foregroundColor(.red)
                                    Text("analysis.usb.missing.description", tableName: "Analysis").font(.caption).foregroundColor(.red.opacity(0.8))
                                }
                            }
                        }
                    } else if !logic.presentedUSBTargets.isEmpty {
                        HStack {
                            if needsExplicitReselectionAction {
                                unavailableSelectionMenu
                            } else {
                                Picker("", selection: Binding(get: { logic.selectedDriveSelectionID }, set: { logic.selectUSBTarget($0) })) {
                                    Text("analysis.usb.target.placeholder", tableName: "Analysis").tag(nil as String?)
                                    if let preservedPickerSelection {
                                        Text(pickerDisplayName(for: preservedPickerSelection))
                                            .tag(Optional(preservedPickerSelection.selectionID))
                                    }
                                    ForEach(logic.presentedUSBTargets) { drive in
                                        Text(pickerDisplayName(for: drive)).tag(Optional(drive.selectionID))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .disabled(!isSelectionEnabled)
            .opacity(isSelectionEnabled ? 1.0 : 0.5)

            if let notice = logic.usbDiscoveryNotice {
                AnalysisUSBDiscoveryNoticeView(logic: logic, notice: notice, sectionIconFont: sectionIconFont)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if logic.selectedDrive != nil {
                if case .insufficient = logic.usbTargetReadiness {
                    StatusCard(tone: .error, density: .compact) {
                        HStack {
                            Image(systemName: "xmark.circle.fill").font(sectionIconFont).foregroundColor(.red).frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading) {
                                if logic.selectedDrive?.isWholeDiskTarget == false {
                                    Text("analysis.usb.volume_capacity_too_small.title", tableName: "Analysis")
                                        .font(.headline).foregroundColor(.red)
                                } else {
                                    Text("analysis.usb.capacity_too_small.title", tableName: "Analysis")
                                        .font(.headline).foregroundColor(.red)
                                }
                                Text(
                                    String(
                                        format: String(localized: "analysis.usb.capacity_too_small.description", table: "Analysis"),
                                        logic.selectedDrive?.isWholeDiskTarget == false
                                            ? logic.requiredVolumeCapacityDisplayValue
                                            : logic.requiredUSBCapacityDisplayValue
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                    .transition(.opacity)
                }
                if logic.isUSBAvailabilityConfirmationExpired {
                    StatusCard(tone: .warning, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill").font(sectionIconFont).foregroundColor(.orange).frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading) {
                                Text("analysis.usb.discovery.availability.title", tableName: "Analysis").font(.headline).foregroundColor(.orange)
                                Text("analysis.usb.discovery.availability.description", tableName: "Analysis").font(.subheadline).foregroundColor(.orange.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                // The warning follows target selection, independently of
                // activity and verification. Readiness gates Continue only.
                VStack(alignment: .leading, spacing: 15) {
                    StatusCard(tone: .warning, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill").font(sectionIconFont).foregroundColor(.orange).frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading) {
                                Text("analysis.usb.destructive.title", tableName: "Analysis").font(.headline).foregroundColor(.orange)
                                Text("analysis.usb.destructive.description", tableName: "Analysis").font(.subheadline).foregroundColor(.orange.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: logic.usbDiscoveryNotice)
        .animation(.easeInOut(duration: 0.24), value: logic.usbTargetReadiness)
    }
}
