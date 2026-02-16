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
    @Binding var isHelperWorking: Bool
    @Binding var isCancelling: Bool
    @Binding var navigateToFinish: Bool
    @Binding var helperOperationFailed: Bool
    @Binding var didCancelCreation: Bool
    @Binding var creationStartedAt: Date?

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
                VStack(alignment: .leading, spacing: 15) {
                    Text("Tworzenie nośnika")
                        .font(.title)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 5)

                    HStack {
                        if let detectedSystemIcon {
                            Image(nsImage: detectedSystemIcon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "applelogo")
                                .font(.title2)
                                .foregroundColor(.green)
                                .frame(width: 32)
                        }
                        VStack(alignment: .leading) {
                            Text("Wybrany system")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(systemName)
                                .font(.headline)
                                .foregroundColor(.green)
                                .bold()
                        }
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)

                    Divider()

                    VStack(spacing: 10) {
                        ForEach(Array(stageDescriptors.enumerated()), id: \.element.id) { index, stage in
                            stageRow(for: stage, at: index)
                        }
                    }
                }
                .padding()
            }

            VStack(spacing: 0) {
                Divider()

                VStack(spacing: 12) {
                    Button(action: onCancelRequested) {
                        HStack {
                            Text(isCancelling ? "Przerywanie..." : "Przerwij")
                            Image(systemName: "xmark.circle")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.gray.opacity(0.2))
                    .disabled(isCancelling || !canCancelWorkflow)
                    .opacity((isCancelling || !canCancelWorkflow) ? 0.5 : 1.0)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: 550, height: 750)
        .navigationTitle("macUSB")
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
                    creationStartedAt: creationStartedAt
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
            HStack(spacing: 12) {
                Image(systemName: iconForStage(stage.key))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                Text(LocalizedStringKey(stage.titleKey))
                    .font(.headline)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

        case .active:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: iconForStage(stage.key))
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    Text(LocalizedStringKey(stage.titleKey))
                        .font(.headline)
                    Spacer()
                }
                Text(LocalizedStringKey(helperStatusKey.isEmpty ? "Nawiązywanie połączenia XPC..." : helperStatusKey))
                    .font(.caption)
                    .foregroundColor(.secondary)
                ProgressView()
                    .progressViewStyle(.linear)
                if shouldShowWriteSpeed(for: stage.key) {
                    Text(verbatim: writeSpeedLabelText())
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)

        case .completed:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
                    .frame(width: 24)
                Text(LocalizedStringKey(stage.titleKey))
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
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

        if let currentIndex = stageDescriptors.firstIndex(where: { $0.key == helperCurrentStageKey }) {
            if index < currentIndex {
                return .completed
            }
            if index == currentIndex {
                return .active
            }
            return .pending
        }

        if (isHelperWorking || isCancelling) && helperCurrentStageKey.isEmpty {
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
        case "catalina_cleanup", "cleanup_temp":
            return "trash.fill"
        case "catalina_xattr":
            return "checkmark.shield.fill"
        default:
            return "gearshape.2"
        }
    }

    private func shouldShowWriteSpeed(for stageKey: String) -> Bool {
        switch stageKey {
        case "imagescan", "restore", "ppc_restore", "createinstallmedia", "catalina_copy":
            return true
        default:
            return false
        }
    }

    private func writeSpeedLabelText() -> String {
        let normalized = helperWriteSpeedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let rawValue = normalized.split(separator: " ").first.map(String.init) ?? ""

        guard let measured = Double(rawValue), measured.isFinite else {
            return "Szybkość zapisu: - MB/s"
        }

        let rounded = max(0, Int(measured.rounded()))
        return "Szybkość zapisu: \(rounded) MB/s"
    }
}
