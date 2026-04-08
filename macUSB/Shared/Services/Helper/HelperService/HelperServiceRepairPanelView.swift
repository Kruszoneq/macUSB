import SwiftUI
import Combine

@MainActor
final class HelperRepairPanelPresentationModel: ObservableObject {
    @Published var statusTitle: String = String(localized: "Przygotowuję naprawę helpera")
    @Published var statusDetail: String = String(localized: "Odświeżam usługę systemową i weryfikuję gotowość")
    @Published var statusResult: Bool? = nil
    @Published var statusSymbolName: String = "wrench.and.screwdriver.fill"
    @Published var logLines: [String] = []
    @Published var isRunning: Bool = true
    @Published var closeEnabled: Bool = false
    @Published var isDetailsExpanded: Bool = false

    var onClose: (() -> Void)?
    var onToggleDetails: ((Bool) -> Void)?

    var joinedLogs: String {
        logLines.joined(separator: "\n")
    }

    func appendLog(_ line: String) {
        logLines.append(line)
    }

    func clearLogs() {
        logLines.removeAll(keepingCapacity: true)
    }

    func requestClose() {
        onClose?()
    }

    func toggleDetails() {
        isDetailsExpanded.toggle()
        onToggleDetails?(isDetailsExpanded)
    }

    func setDetailsExpanded(_ expanded: Bool, notify: Bool) {
        isDetailsExpanded = expanded
        if notify {
            onToggleDetails?(expanded)
        }
    }
}

struct HelperRepairPanelView: View {
    @ObservedObject var model: HelperRepairPanelPresentationModel

    private var statusTone: MacUSBSurfaceTone {
        switch model.statusResult {
        case .some(true): return .success
        case .some(false): return .error
        case .none: return .neutral
        }
    }

    private var statusIconColor: Color {
        switch model.statusResult {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
            StatusCard(tone: .subtle, density: .compact) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: MacUSBDesignTokens.iconColumnWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Naprawa helpera systemowego"))
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(String(localized: "Odświeżam rejestrację helpera i potwierdzam gotowość do pracy"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.30))
                    .frame(height: 1)
                Text(String(localized: "Postęp naprawy"))
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.30))
                    .frame(height: 1)
            }

            StatusCard(tone: statusTone) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: model.statusSymbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(statusIconColor)
                            .frame(width: MacUSBDesignTokens.iconColumnWidth, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.statusTitle)
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text(model.statusDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if model.isRunning {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button(model.isDetailsExpanded
                       ? String(localized: "Ukryj dziennik techniczny")
                       : String(localized: "Pokaż dziennik techniczny")) {
                    model.toggleDetails()
                }
                .macUSBSecondaryButtonStyle()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.bottom, model.isDetailsExpanded ? 0 : 10)

            if model.isDetailsExpanded {
                StatusCard(tone: .neutral, density: .compact) {
                    ScrollView {
                        Text(model.joinedLogs.isEmpty ? String(localized: "Brak wpisów dziennika") : model.joinedLogs)
                            .textSelection(.enabled)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, MacUSBDesignTokens.contentHorizontalPadding)
        .padding(.top, MacUSBDesignTokens.contentVerticalPadding)
        .frame(width: MacUSBDesignTokens.windowWidth, alignment: .top)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    model.requestClose()
                } label: {
                    HStack {
                        Text(String(localized: "Zamknij"))
                        Image(systemName: "xmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .disabled(!model.closeEnabled)
                .macUSBPrimaryButtonStyle(isEnabled: model.closeEnabled)
            }
        }
        .animation(.easeInOut(duration: 0.20), value: model.isDetailsExpanded)
    }
}
