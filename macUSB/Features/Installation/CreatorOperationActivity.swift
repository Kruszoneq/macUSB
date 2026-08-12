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
        finishWorkflowCleanupOperationIfNeeded()
        usbCreationOperationToken?.finish()
        usbCreationOperationToken = nil
    }

    func updateWorkflowCleanupOperation(for stageKey: String) {
        let normalizedStageKey = stageKey.lowercased()
        let isCleanupStage = normalizedStageKey.contains("cleanup")
        if isCleanupStage {
            guard workflowCleanupOperationToken == nil else { return }
            workflowCleanupOperationToken = AppActiveOperationRegistry.shared.begin(
                kind: .cleanup,
                context: "helper_workflow_stage:\(normalizedStageKey)"
            )
        } else {
            finishWorkflowCleanupOperationIfNeeded()
        }
    }

    func finishWorkflowCleanupOperationIfNeeded() {
        workflowCleanupOperationToken?.finish()
        workflowCleanupOperationToken = nil
    }
}
