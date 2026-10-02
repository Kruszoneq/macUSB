import SwiftUI

struct CreatorWindowsPrerequisiteCardView: View {
    let hasHomebrew: Bool
    let isRefreshing: Bool
    let onOpenHomebrewWebsite: () -> Void
    let onRefreshProbe: () -> Void

    private var iconColumnWidth: CGFloat { MacUSBDesignTokens.iconColumnWidth }
    private var sectionIconFont: Font { .title3 }
    private let brewInstallCommand = "brew install wimlib"

    var body: some View {
        StatusCard(tone: .warning, density: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(sectionIconFont)
                        .foregroundColor(.orange)
                        .frame(width: iconColumnWidth)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "creator.windows.summary.wimlib.required.title", table: "Creator"))
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text(String(localized: "creator.windows.summary.wimlib.required.body", table: "Creator"))
                            .font(.subheadline)
                            .foregroundColor(.orange.opacity(0.9))
                    }

                    Spacer()
                }

                Divider()
                    .overlay(Color.orange.opacity(0.25))

                HStack(alignment: .center) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(sectionIconFont)
                        .foregroundColor(.orange)
                        .frame(width: iconColumnWidth)

                    VStack(alignment: .leading, spacing: 2) {
                        if hasHomebrew {
                            Text(String(localized: "creator.windows.summary.wimlib.brew_available.title", table: "Creator"))
                                .font(.headline)
                                .foregroundColor(.orange)
                            styledInstructionWithCommand(
                                String(localized: "creator.windows.summary.wimlib.brew_available.body", table: "Creator")
                            )
                        } else {
                            Text(String(localized: "creator.windows.summary.wimlib.brew_missing.title", table: "Creator"))
                                .font(.headline)
                                .foregroundColor(.orange)
                            styledInstructionWithCommand(
                                String(localized: "creator.windows.summary.wimlib.brew_missing.body", table: "Creator")
                            )
                        }
                    }

                    Spacer()
                }

                VStack(spacing: MacUSBDesignTokens.bottomBarContentSpacing) {
                    if !hasHomebrew {
                        Button(action: onOpenHomebrewWebsite) {
                            HStack {
                                Text(String(localized: "creator.windows.summary.wimlib.open_homebrew.button", table: "Creator"))
                                Image(systemName: "safari")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .macUSBSecondaryButtonStyle()
                    }

                    Button(action: onRefreshProbe) {
                        HStack {
                            Text(String(localized: "creator.windows.summary.wimlib.refresh.button", table: "Creator"))
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }
                    .macUSBSecondaryButtonStyle(isEnabled: !isRefreshing)
                    .disabled(isRefreshing)
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func styledInstructionWithCommand(_ localizedBody: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localizedBody)
                .font(.subheadline)
                .foregroundColor(.orange.opacity(0.9))
            Text(brewInstallCommand)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(.orange.opacity(0.95))
        }
    }
}
