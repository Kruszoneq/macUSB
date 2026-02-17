import SwiftUI
import AppKit

private enum CreationStageVisualState {
    case pending
    case active
    case completed
}

private struct CreationStageDescriptor: Identifiable {
    let key: String
    let titleKey: String

    var id: String { key }
}

struct CreationProgressView: View {
    let systemName: String
    let mountPoint: URL
    let detectedSystemIcon: NSImage?
    let isCatalina: Bool
    let isRestoreLegacy: Bool
    let isMavericks: Bool
    let isPPC: Bool
    let needsPreformat: Bool
    let onReset: () -> Void
    let onCancelRequested: () -> Void
    let canCancelWorkflow: Bool

    @Binding var helperStageTitleKey: String
    @Binding var helperStatusKey: String
    @Binding var helperCurrentStageKey: String
    @Binding var helperWriteSpeedText: String
    @Binding var helperCopyProgressPercent: Double
    @Binding var isHelperWorking: Bool
    @Binding var isCancelling: Bool
    @Binding var navigateToFinish: Bool
    @Binding var helperOperationFailed: Bool
    @Binding var didCancelCreation: Bool
    @Binding var creationStartedAt: Date?
    private var sectionIconFont: Font { .title3 }
    private var stageSectionDivider: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
            Text("Etapy tworzenia")
                .font(.caption)
                .foregroundColor(.secondary)
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var stageDescriptors: [CreationStageDescriptor] {
        var stageKeys: [String] = ["prepare_source"]

        if isPPC {
            stageKeys.append("ppc_format")
            stageKeys.append("ppc_restore")
            stageKeys.append("cleanup_temp")
            return stageKeys.map(stageDescriptor(for:))
        }

        if needsPreformat {
            stageKeys.append("preformat")
        }

        if isRestoreLegacy || isMavericks {
            stageKeys.append("imagescan")
            stageKeys.append("restore")
        } else {
            stageKeys.append("createinstallmedia")
            if isCatalina {
                stageKeys.append("catalina_cleanup")
                stageKeys.append("catalina_copy")
                stageKeys.append("catalina_xattr")
            }
        }

        stageKeys.append("cleanup_temp")
        return stageKeys.map(stageDescriptor(for:))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
                    StatusCard(tone: .subtle, density: .compact) {
                        HStack {
                            if let detectedSystemIcon {
                                Image(nsImage: detectedSystemIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "applelogo")
                                    .font(sectionIconFont)
                                    .foregroundColor(.secondary)
                                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            }
                            VStack(alignment: .leading) {
                                Text("Wybrany system")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(systemName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .bold()
                            }
                            Spacer()
                        }
                    }

                    stageSectionDivider

                    VStack(spacing: 10) {
                        ForEach(Array(stageDescriptors.enumerated()), id: \.element.id) { index, stage in
                            stageRow(for: stage, at: index)
                        }
                    }
                }
                .padding(.horizontal, MacUSBDesignTokens.contentHorizontalPadding)
                .padding(.vertical, MacUSBDesignTokens.contentVerticalPadding)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button(action: onCancelRequested) {
                    HStack {
                        Text(isCancelling ? "Przerywanie..." : "Przerwij")
                        Image(systemName: "xmark.circle")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .macUSBSecondaryButtonStyle(isEnabled: !(isCancelling || !canCancelWorkflow))
                .disabled(isCancelling || !canCancelWorkflow)
            }
        }
        .frame(width: MacUSBDesignTokens.windowWidth, height: MacUSBDesignTokens.windowHeight)
        .navigationTitle("Tworzenie nośnika")
        .navigationBarBackButtonHidden(true)
        .background(
            NavigationLink(
                destination: FinishUSBView(
                    systemName: systemName,
                    mountPoint: mountPoint,
                    onReset: onReset,
                    isPPC: isPPC,
                    didFail: helperOperationFailed,
                    didCancel: didCancelCreation,
                    creationStartedAt: creationStartedAt,
                    detectedSystemIcon: detectedSystemIcon
                ),
                isActive: $navigateToFinish
            ) { EmptyView() }
            .hidden()
        )
    }

    @ViewBuilder
    private func stageRow(for stage: CreationStageDescriptor, at index: Int) -> some View {
        let stageState = stateForStage(at: index)

        switch stageState {
        case .pending:
            StatusCard(tone: .subtle, density: .compact) {
                HStack(spacing: 12) {
                    Image(systemName: iconForStage(stage.key))
                        .font(sectionIconFont)
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                    Text(LocalizedStringKey(stage.titleKey))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

        case .active:
            StatusCard(
                tone: .active,
                cornerRadius: MacUSBDesignTokens.prominentPanelCornerRadius(for: currentVisualMode())
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: iconForStage(stage.key))
                            .font(sectionIconFont)
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        Text(LocalizedStringKey(stage.titleKey))
                            .font(.headline)
                        Spacer()
                        if shouldShowCopyProgress(for: stage.key) {
                            Text(copyProgressText())
                                .font(.title3.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }
                    }
                    Text(LocalizedStringKey(helperStatusKey.isEmpty ? "Rozpoczynanie..." : helperStatusKey))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if shouldShowCopyProgress(for: stage.key) {
                        ProgressView(value: boundedCopyProgressPercent() / 100.0)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    if shouldShowWriteSpeed(for: stage.key) {
                        Text(verbatim: writeSpeedLabelText())
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }

        case .completed:
            StatusCard(tone: .neutral, density: .compact) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(sectionIconFont)
                        .foregroundColor(.green)
                        .frame(width: 24)
                    Text(LocalizedStringKey(stage.titleKey))
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
    }

    private func stageDescriptor(for stageKey: String) -> CreationStageDescriptor {
        if let presentation = HelperWorkflowLocalizationKeys.presentation(for: stageKey) {
            return CreationStageDescriptor(key: stageKey, titleKey: presentation.titleKey)
        }
        return CreationStageDescriptor(key: stageKey, titleKey: stageKey)
    }

    private func stateForStage(at index: Int) -> CreationStageVisualState {
        if helperCurrentStageKey == "finalize" || navigateToFinish {
            return .completed
        }

        let currentStageKey = normalizedStageKey(helperCurrentStageKey)

        if let currentIndex = stageDescriptors.firstIndex(where: { $0.key == currentStageKey }) {
            if index < currentIndex {
                return .completed
            }
            if index == currentIndex {
                return .active
            }
            return .pending
        }

        if !helperStageTitleKey.isEmpty,
           let titleIndex = stageDescriptors.firstIndex(where: { $0.titleKey == helperStageTitleKey }) {
            if index < titleIndex {
                return .completed
            }
            if index == titleIndex {
                return .active
            }
            return .pending
        }

        if helperCurrentStageKey.isEmpty && (!helperStatusKey.isEmpty || isHelperWorking || isCancelling) {
            return index == 0 ? .active : .pending
        }

        return .pending
    }

    private func iconForStage(_ stageKey: String) -> String {
        switch stageKey {
        case "prepare_source":
            return "tray.and.arrow.down.fill"
        case "preformat", "ppc_format":
            return "externaldrive.fill"
        case "imagescan":
            return "magnifyingglass"
        case "restore", "ppc_restore", "catalina_copy":
            return "doc.on.doc.fill"
        case "createinstallmedia":
            return "externaldrive.badge.plus"
        case "catalina_cleanup":
            return "doc.badge.gearshape"
        case "cleanup_temp":
            return "trash.fill"
        case "catalina_xattr":
            return "checkmark.shield.fill"
        default:
            return "gearshape.2"
        }
    }

    private func shouldShowWriteSpeed(for stageKey: String) -> Bool {
        switch stageKey {
        case "restore", "ppc_restore", "createinstallmedia", "catalina_copy":
            return true
        default:
            return false
        }
    }

    private func shouldShowCopyProgress(for stageKey: String) -> Bool {
        switch stageKey {
        case "restore", "ppc_restore", "createinstallmedia", "catalina_copy":
            return true
        default:
            return false
        }
    }

    private func boundedCopyProgressPercent() -> Double {
        min(max(helperCopyProgressPercent, 0), 99)
    }

    private func copyProgressText() -> String {
        "\(Int(boundedCopyProgressPercent().rounded()))%"
    }

    private func writeSpeedLabelText() -> String {
        let normalized = helperWriteSpeedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let rawValue = normalized.split(separator: " ").first.map(String.init) ?? ""

        guard let measured = Double(rawValue), measured.isFinite else {
            return String(localized: "Szybkość zapisu: - MB/s")
        }

        let rounded = max(0, Int(measured.rounded()))
        return String(
            format: String(localized: "Szybkość zapisu: %d MB/s"),
            rounded
        )
    }

    private func normalizedStageKey(_ rawStageKey: String) -> String {
        switch rawStageKey {
        case "catalina_ditto", "ditto":
            return "catalina_copy"
        case "catalina_finalize":
            return "catalina_cleanup"
        case "asr_imagescan":
            return "imagescan"
        case "asr_restore":
            return "restore"
        default:
            return rawStageKey
        }
    }
}
