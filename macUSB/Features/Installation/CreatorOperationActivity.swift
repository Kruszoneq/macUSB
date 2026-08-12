import Foundation

extension UniversalInstallationView {
    func beginUSBCreationOperationIfNeeded() {
        guard usbCreationOperationToken == nil else { return }
        let workflow: String
        if isLinuxWorkflow {
            workflow = "linux"
        } else if isWindowsWorkflow {
            workflow = "windows"
        } else if isPPC {
            workflow = "macos_ppc"
        } else if isRestoreLegacy {
            workflow = "macos_restore_legacy"
        } else if isMavericks {
            workflow = "macos_mavericks"
        } else if isCatalina {
            workflow = "macos_catalina"
        } else if isSierra {
            workflow = "macos_sierra"
        } else {
            workflow = "macos_standard"
        }
        usbCreationOperationToken = AppActiveOperationRegistry.shared.begin(
            kind: .usbCreation,
            context: "usb_creation:\(workflow)"
        )
    }

    func finishUSBCreationOperationIfNeeded() {
        usbCreationOperationToken?.finish()
        usbCreationOperationToken = nil
    }
}
