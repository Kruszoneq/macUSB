import SwiftUI

struct CreatorMacOSRosettaCardView: View {
    let state: CreatorMacOSRosettaState
    let action: () -> Void

    private var titleKey: String {
        switch state {
        case .missing, .installing:
            return "installation.summary.rosetta.missing.title"
        case .checking, .checkFailed:
            return "installation.summary.rosetta.check_failed.title"
        case .installFailed:
            return "installation.summary.rosetta.install_failed.title"
        case .notAvailable:
            return "installation.summary.rosetta.not_available.title"
        case .available:
            return ""
        }
    }

    private var descriptionKey: String {
        switch state {
        case .missing, .installing:
            return "installation.summary.rosetta.missing.description"
        case .checking, .checkFailed:
            return "installation.summary.rosetta.check_failed.description"
        case .installFailed:
            return "installation.summary.rosetta.install_failed.description"
        case .notAvailable:
            return "installation.summary.rosetta.not_available.description"
        case .available:
            return ""
        }
    }

    private var actionKey: String {
        switch state {
        case .missing:
            return "installation.summary.rosetta.install.action"
        case .installing:
            return "installation.summary.rosetta.installing.action"
        case .checking, .checkFailed, .notAvailable:
            return "installation.summary.rosetta.check.action"
        case .installFailed:
            return "installation.summary.rosetta.retry.action"
        case .available:
            return ""
        }
    }

    var body: some View {
        StatusCard(tone: .warning, density: .compact) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                    .frame(width: MacUSBDesignTokens.iconColumnWidth)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: String.LocalizationValue(titleKey)))
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text(String(localized: String.LocalizationValue(descriptionKey)))
                            .font(.subheadline)
                            .foregroundColor(.orange.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(String(localized: String.LocalizationValue(actionKey)), action: action)
                        .buttonStyle(.bordered)
                        .disabled(state == .installing || state == .checking)
                }
                Spacer()
            }
        }
    }
}
