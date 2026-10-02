import SwiftUI

struct CreatorWindowsAutounattendOptionsSheetView: View {
    let windowsVersion: CreatorWindowsAutounattendWindowsVersion
    @Binding var configuration: CreatorWindowsAutounattendConfiguration
    let onConfigurationChanged: (CreatorWindowsAutounattendConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss

    private var shouldShowLocalAccountDisplayNameInvalidCharacters: Bool {
        let displayName = configuration.localAccountDisplayName
        return !displayName.isEmpty
            && CreatorWindowsAutounattendConfiguration.containsInvalidLocalAccountDisplayNameCharacter(displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .foregroundColor(.white)
                    Text(String(localized: "creator.windows.summary.autounattend.card.title", table: "Creator"))
                        .font(.headline)
                    Spacer()
                }

                Divider()
            }

            if windowsVersion.supportsHardwareBypass {
                Toggle(
                    String(localized: "creator.windows.summary.autounattend.option.hardware_bypass", table: "Creator"),
                    isOn: binding(\.skipHardwareRequirements)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    String(localized: "creator.windows.summary.autounattend.option.use_mac_language_region", table: "Creator"),
                    isOn: binding(\.useMacLanguageAndRegion)
                )
                .disabled(!configuration.canUseMacLanguageAndRegion)
                .opacity(configuration.canUseMacLanguageAndRegion ? 1 : 0.55)

                if !configuration.canUseMacLanguageAndRegion {
                    Text(String(localized: "creator.windows.summary.autounattend.option.use_mac_language_region.unavailable", table: "Creator"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Toggle(
                String(localized: "creator.windows.summary.autounattend.option.prevent_device_encryption", table: "Creator"),
                isOn: binding(\.preventDeviceEncryption)
            )

            Toggle(
                String(localized: "creator.windows.summary.autounattend.option.disable_data_collection", table: "Creator"),
                isOn: binding(\.disableDataCollection)
            )

            Toggle(
                String(localized: "creator.windows.summary.autounattend.option.skip_wireless_setup", table: "Creator"),
                isOn: binding(\.skipWirelessSetup)
            )

            Toggle(
                String(localized: "creator.windows.summary.autounattend.option.skip_microsoft_account", table: "Creator"),
                isOn: binding(\.skipMicrosoftAccountRequirement)
            )
            .disabled(configuration.skipWirelessSetup)
            .opacity(configuration.skipWirelessSetup ? 0.55 : 1)

            Toggle(
                String(localized: "creator.windows.summary.autounattend.option.local_account", table: "Creator"),
                isOn: binding(\.createLocalAccount)
            )
            .disabled(!configuration.skipMicrosoftAccountRequirement)
            .opacity(configuration.skipMicrosoftAccountRequirement ? 1 : 0.55)

            if configuration.createLocalAccount {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "creator.windows.summary.autounattend.account_name.label", table: "Creator"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField(
                        String(localized: "creator.windows.summary.autounattend.account_name.placeholder", table: "Creator"),
                        text: binding(\.localAccountDisplayName)
                    )
                    .textFieldStyle(.roundedBorder)

                    if shouldShowLocalAccountDisplayNameInvalidCharacters {
                        Text(String(localized: "creator.windows.summary.autounattend.account_name.invalid_characters", table: "Creator"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Text(String(localized: "creator.windows.summary.autounattend.account_name.first_boot_password_note", table: "Creator"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "creator.windows.summary.autounattend.done.button", table: "Creator"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .macUSBPrimaryButtonStyle(isEnabled: configuration.canDismissOptionsSheet)
                .disabled(!configuration.canDismissOptionsSheet)
            }
        }
        .toggleStyle(.checkbox)
        .font(.subheadline)
        .padding(18)
        .frame(width: 380)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CreatorWindowsAutounattendConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: {
                configuration[keyPath: keyPath]
            },
            set: { newValue in
                configuration[keyPath: keyPath] = newValue
                configuration.existingFileDecision = nil
                configuration.normalize(for: windowsVersion)
                onConfigurationChanged(configuration)
            }
        )
    }
}
