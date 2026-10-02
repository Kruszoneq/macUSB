import SwiftUI

struct CreatorMacOSRosettaCardView: View {
    let state: CreatorMacOSRosettaState
    let action: () -> Void

    private var isActionEnabled: Bool {
        switch state {
        case .missing, .checkFailed, .installFailed, .notAvailable:
            return true
        case .available, .installing, .checking:
            return false
        }
    }

    private var tone: MacUSBSurfaceTone {
        state == .available ? .success : .warning
    }

    private var tint: Color {
        state == .available ? .green : .orange
    }

    private var iconName: String {
        state == .available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var titleKey: String {
        switch state {
        case .available, .missing, .installing:
            return "creator.macos.rosetta.missing.title"
        case .checking, .checkFailed:
            return "creator.macos.rosetta.check_failed.title"
        case .installFailed:
            return "creator.macos.rosetta.install_failed.title"
        case .notAvailable:
            return "creator.macos.rosetta.not_available.title"
        }
    }

    private var descriptionKey: String {
        switch state {
        case .available, .missing, .installing:
            return "creator.macos.rosetta.missing.description"
        case .checking, .checkFailed:
            return "creator.macos.rosetta.check_failed.description"
        case .installFailed:
            return "creator.macos.rosetta.install_failed.description"
        case .notAvailable:
            return "creator.macos.rosetta.not_available.description"
        }
    }

    private var actionKey: String {
        switch state {
        case .missing:
            return "creator.macos.rosetta.install.action"
        case .installing:
            return "creator.macos.rosetta.installing.action"
        case .checking, .checkFailed, .notAvailable:
            return "creator.macos.rosetta.check.action"
        case .installFailed:
            return "creator.macos.rosetta.retry.action"
        case .available:
            return "creator.macos.rosetta.installed.action"
        }
    }

    var body: some View {
        StatusCard(tone: tone, density: .compact) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundColor(tint)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: MacUSBDesignTokens.iconColumnWidth)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: String.LocalizationValue(titleKey), table: "Creator"))
                            .font(.headline)
                            .foregroundColor(tint)
                        Text(String(localized: String.LocalizationValue(descriptionKey), table: "Creator"))
                            .font(.subheadline)
                            .foregroundColor(tint.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                Button(action: action) {
                    HStack {
                        Text(String(localized: String.LocalizationValue(actionKey), table: "Creator"))
                            .contentTransition(.opacity)
                    }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
                .tint(tint)
                .macUSBSecondaryButtonStyle(isEnabled: isActionEnabled)
                .disabled(!isActionEnabled)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: state)
    }
}
