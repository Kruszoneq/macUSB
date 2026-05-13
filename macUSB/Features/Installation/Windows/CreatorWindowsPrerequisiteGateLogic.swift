import Foundation
import AppKit

extension UniversalInstallationView {
    var windowsPrerequisiteShouldBlockStart: Bool {
        guard isWindowsWorkflow, windowsWillSplitWim else { return false }
        return windowsPrerequisiteToolchainPresence?.hasWimlib != true
    }

    var windowsPrerequisiteHasHomebrew: Bool {
        windowsPrerequisiteToolchainPresence?.hasHomebrew == true
    }

    func refreshWindowsPrerequisiteToolchainPresence() {
        guard isWindowsWorkflow else { return }
        windowsPrerequisiteProbeInProgress = true
        log("WindowsPrerequisiteGate: refresh toolchain probe requested", category: "WindowsInstallFlow")

        DispatchQueue.global(qos: .userInitiated).async {
            let presence = WindowsToolchainProbeService.shared.detectPresence()

            DispatchQueue.main.async {
                self.windowsPrerequisiteToolchainPresence = presence
                self.windowsPrerequisiteProbeInProgress = false
                self.log(
                    "WindowsPrerequisiteGate: toolchain presence brew=\(presence.hasHomebrew), wimlib=\(presence.hasWimlib)",
                    category: "WindowsInstallFlow"
                )
                self.log(
                    "WindowsPrerequisiteGate: toolchain paths brew=\(presence.homebrewPath ?? "not_found"), wimlib=\(presence.wimlibPath ?? "not_found")",
                    category: "WindowsInstallFlow"
                )
                self.log(
                    "WindowsPrerequisiteGate: start blocked=\(self.windowsPrerequisiteShouldBlockStart ? "TAK" : "NIE")",
                    category: "WindowsInstallFlow"
                )
            }
        }
    }

    func openHomebrewWebsite() {
        guard let url = URL(string: "https://brew.sh") else { return }
        NSWorkspace.shared.open(url)
    }
}
