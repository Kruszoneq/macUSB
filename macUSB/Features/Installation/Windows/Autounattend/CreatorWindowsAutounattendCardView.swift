import SwiftUI

struct CreatorWindowsAutounattendDividerView: View {
    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
            Text(String(localized: "installation.summary.windows.autounattend.divider"))
                .font(.caption)
                .foregroundColor(.secondary)
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
}

struct CreatorWindowsAutounattendCardView: View {
    let windowsVersion: CreatorWindowsAutounattendWindowsVersion
    @Binding var configuration: CreatorWindowsAutounattendConfiguration
    @Binding var isOptionsPresented: Bool
    let onConfigurationChanged: (CreatorWindowsAutounattendConfiguration) -> Void

    private var selectedSummary: String? {
        let selectedCount = [
            configuration.skipHardwareRequirements,
            configuration.preventDeviceEncryption,
            configuration.disableDataCollection,
            configuration.skipWirelessSetup,
            configuration.skipMicrosoftAccountRequirement,
            configuration.createLocalAccount
        ].filter { $0 }.count

        guard selectedCount > 0 else { return nil }
        return String(
            format: String(localized: "installation.summary.windows.autounattend.selected_count"),
            selectedCount
        )
    }

    var body: some View {
        StatusCard(tone: .active, density: .compact) {
            HStack(alignment: .top) {
                Image(systemName: "gearshape.2")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: MacUSBDesignTokens.iconColumnWidth)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "installation.summary.windows.autounattend.card.title"))
                            .font(.headline)
                            .foregroundColor(.accentColor)
                        Text(String(localized: "installation.summary.windows.autounattend.card.body"))
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                    }

                    if let selectedSummary {
                        Text(selectedSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: { isOptionsPresented = true }) {
                        HStack {
                            Text(String(localized: "installation.summary.windows.autounattend.configure.button"))
                            Image(systemName: "slider.horizontal.3")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }
                    .macUSBSecondaryButtonStyle()
                    .sheet(isPresented: $isOptionsPresented) {
                        CreatorWindowsAutounattendOptionsSheetView(
                            windowsVersion: windowsVersion,
                            configuration: $configuration,
                            onConfigurationChanged: onConfigurationChanged
                        )
                    }
                }

                Spacer()
            }
        }
        .transition(.opacity)
    }
}
