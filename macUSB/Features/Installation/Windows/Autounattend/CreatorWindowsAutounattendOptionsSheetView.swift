import SwiftUI

struct CreatorWindowsAutounattendOptionsSheetView: View {
    let windowsVersion: CreatorWindowsAutounattendWindowsVersion
    @Binding var configuration: CreatorWindowsAutounattendConfiguration
    let onConfigurationChanged: (CreatorWindowsAutounattendConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .foregroundColor(.white)
                    Text(String(localized: "installation.summary.windows.autounattend.card.title"))
                        .font(.headline)
                    Spacer()
                }

                Divider()
            }

            if windowsVersion.supportsHardwareBypass {
                Toggle(
                    String(localized: "installation.summary.windows.autounattend.option.hardware_bypass"),
                    isOn: binding(\.skipHardwareRequirements)
                )
            }

            Toggle(
                String(localized: "installation.summary.windows.autounattend.option.prevent_device_encryption"),
                isOn: binding(\.preventDeviceEncryption)
            )

            Toggle(
                String(localized: "installation.summary.windows.autounattend.option.disable_data_collection"),
                isOn: binding(\.disableDataCollection)
            )

            Toggle(
                String(localized: "installation.summary.windows.autounattend.option.skip_wireless_setup"),
                isOn: binding(\.skipWirelessSetup)
            )

            Toggle(
                String(localized: "installation.summary.windows.autounattend.option.skip_microsoft_account"),
                isOn: binding(\.skipMicrosoftAccountRequirement)
            )
            .disabled(configuration.skipWirelessSetup)
            .opacity(configuration.skipWirelessSetup ? 0.55 : 1)

            Toggle(
                String(localized: "installation.summary.windows.autounattend.option.local_account"),
                isOn: binding(\.createLocalAccount)
            )
            .disabled(!configuration.skipMicrosoftAccountRequirement)
            .opacity(configuration.skipMicrosoftAccountRequirement ? 1 : 0.55)

            if configuration.createLocalAccount {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "installation.summary.windows.autounattend.account_name.label"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField(
                        String(localized: "installation.summary.windows.autounattend.account_name.placeholder"),
                        text: binding(\.localAccountName)
                    )
                    .textFieldStyle(.roundedBorder)

                    if !configuration.isLocalAccountNameValid {
                        Text(String(localized: "installation.summary.windows.autounattend.account_name.validation"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "OK"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .macUSBPrimaryButtonStyle()
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
