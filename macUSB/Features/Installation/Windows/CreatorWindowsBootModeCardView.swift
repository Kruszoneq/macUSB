import SwiftUI

enum CreatorWindowsBootModeCardStyle {
    case configurable(selectionEnabled: Bool)
    case biosOnly
    case uefiOnly
}

extension UniversalInstallationView {
    var windowsBootModeCardStyle: CreatorWindowsBootModeCardStyle? {
        guard isWindowsWorkflow, let windowsFamily else { return nil }

        switch windowsFamily {
        case .vista, .seven, .server2008R2:
            return .biosOnly
        case .eight, .eightOne, .ten,
             .server2012, .server2012R2, .server2016, .server2019, .server2022:
            return .configurable(
                selectionEnabled: (windowsBootCapabilities?.eligibleModes.count ?? 0) > 1
            )
        case .eleven, .server2025:
            return .uefiOnly
        case .xp, .server2003:
            return nil
        }
    }

    var preferredWindowsBootMode: WindowsBootMode? {
        guard isWindowsWorkflow, let eligibleModes = windowsBootCapabilities?.eligibleModes else {
            return nil
        }
        if eligibleModes.contains(.uefi) {
            return .uefi
        }
        if eligibleModes.contains(.bios) {
            return .bios
        }
        return nil
    }

    var resolvedWindowsBootMode: WindowsBootMode? {
        selectedWindowsBootMode ?? preferredWindowsBootMode
    }

    var windowsBIOSSelectionShouldBlockStart: Bool {
        isWindowsWorkflow && resolvedWindowsBootMode == .bios
    }

    func initializeWindowsBootModeSelectionIfNeeded() {
        guard selectedWindowsBootMode == nil, let preferredWindowsBootMode else { return }
        selectedWindowsBootMode = preferredWindowsBootMode
        lastLoggedWindowsBootMode = preferredWindowsBootMode
        log(
            "WindowsBootMode: initialized selection=\(preferredWindowsBootMode.rawValue), eligible=\(windowsEligibleBootModesLogValue)",
            category: "WindowsInstallFlow"
        )
    }

    func logWindowsBootModeChangeIfNeeded(_ mode: WindowsBootMode?) {
        guard let mode, mode != lastLoggedWindowsBootMode else { return }
        lastLoggedWindowsBootMode = mode
        log(
            "WindowsBootMode: changed selection=\(mode.rawValue), eligible=\(windowsEligibleBootModesLogValue)",
            category: "WindowsInstallFlow"
        )
    }

    private var windowsEligibleBootModesLogValue: String {
        let eligibleModes = windowsBootCapabilities?.eligibleModes ?? []
        let orderedModes = WindowsBootMode.allCases.filter(eligibleModes.contains).map(\.rawValue)
        return orderedModes.isEmpty ? "none" : orderedModes.joined(separator: "+")
    }
}

struct CreatorWindowsBootModeCardView: View {
    let style: CreatorWindowsBootModeCardStyle
    let eligibleModes: Set<WindowsBootMode>
    @Binding var selectedMode: WindowsBootMode?

    private var sectionIconFont: Font { .title3 }

    var body: some View {
        switch style {
        case .configurable(let selectionEnabled):
            configurableCard(selectionEnabled: selectionEnabled)
        case .biosOnly:
            informationalCard(
                titleKey: "installation.summary.windows.bios_only.title",
                bodyKey: "installation.summary.windows.bios_only.body"
            )
        case .uefiOnly:
            informationalCard(
                titleKey: "installation.summary.windows.uefi_only.title",
                bodyKey: "installation.summary.windows.uefi_only.body"
            )
        }
    }

    private func configurableCard(selectionEnabled: Bool) -> some View {
        StatusCard(tone: .active, density: .compact) {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle.fill")
                        .font(sectionIconFont)
                        .foregroundColor(.accentColor)
                        .frame(width: MacUSBDesignTokens.iconColumnWidth)

                    Text(String(localized: "installation.summary.windows.boot_mode.body"))
                        .font(.headline)
                        .foregroundColor(.accentColor)

                    Spacer()
                }

                Picker(
                    String(localized: "installation.summary.windows.boot_mode.body"),
                    selection: $selectedMode
                ) {
                    Text(verbatim: "BIOS")
                        .tag(Optional(WindowsBootMode.bios))
                        .disabled(!eligibleModes.contains(.bios))
                    Text(verbatim: "UEFI")
                        .tag(Optional(WindowsBootMode.uefi))
                        .disabled(!eligibleModes.contains(.uefi))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(!selectionEnabled)
            }
        }
    }

    private func informationalCard(titleKey: String.LocalizationValue, bodyKey: String.LocalizationValue) -> some View {
        StatusCard(tone: .active, density: .compact) {
            HStack(alignment: .center) {
                Image(systemName: "info.circle.fill")
                    .font(sectionIconFont)
                    .foregroundColor(.accentColor)
                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: titleKey))
                        .font(.headline)
                        .foregroundColor(.accentColor)
                    Text(String(localized: bodyKey))
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
                Spacer()
            }
        }
    }
}
