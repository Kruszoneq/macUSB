import SwiftUI

struct CreatorWindowsAutounattendPopoverView: View {
    let windowsVersion: CreatorWindowsAutounattendWindowsVersion
    @Binding var configuration: CreatorWindowsAutounattendConfiguration
    let onConfigurationChanged: (CreatorWindowsAutounattendConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if windowsVersion.supportsHardwareBypass {
                Toggle(
                    String(localized: "installation.summary.windows.autounattend.option.hardware_bypass"),
                    isOn: binding(\.skipHardwareRequirements)
                )
            }

            Toggle(
                String(localized: "installation.summary.windows.autounattend.option.skip_license"),
                isOn: binding(\.skipLicenseScreen)
            )

            Toggle(
                String(localized: "installation.summary.windows.autounattend.option.local_account"),
                isOn: binding(\.createLocalAccount)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "installation.summary.windows.autounattend.account_name.label"))
                    .font(.caption)
                    .foregroundColor(configuration.createLocalAccount ? .secondary : .secondary.opacity(0.55))

                TextField(
                    String(localized: "installation.summary.windows.autounattend.account_name.placeholder"),
                    text: binding(\.localAccountName)
                )
                .textFieldStyle(.roundedBorder)
                .disabled(!configuration.createLocalAccount)

                if configuration.createLocalAccount && !configuration.isLocalAccountNameValid {
                    Text(String(localized: "installation.summary.windows.autounattend.account_name.validation"))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .toggleStyle(.checkbox)
        .font(.subheadline)
        .padding(16)
        .frame(width: 310)
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
