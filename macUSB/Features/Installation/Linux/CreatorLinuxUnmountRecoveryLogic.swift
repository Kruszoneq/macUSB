import Foundation
import AppKit
import SwiftUI

extension UniversalInstallationView {
    func shouldPromptLinuxForceUnmountAlert(for result: HelperWorkflowResultPayload) -> Bool {
        guard isLinuxWorkflow else { return false }
        guard !result.success else { return false }
        guard result.failedStage == "linux_unmount_target" else { return false }
        guard let message = result.errorMessage?.lowercased() else { return false }
        return message.contains("linux_unmount_busy_prompt")
    }

    func makeLinuxForceUnmountRequest(from request: HelperWorkflowRequestPayload) -> HelperWorkflowRequestPayload {
        HelperWorkflowRequestPayload(
            workflowKind: request.workflowKind,
            systemName: request.systemName,
            sourceAppPath: request.sourceAppPath,
            originalImagePath: request.originalImagePath,
            tempWorkPath: request.tempWorkPath,
            targetVolumePath: request.targetVolumePath,
            targetBSDName: request.targetBSDName,
            targetLabel: request.targetLabel,
            needsPreformat: request.needsPreformat,
            isCatalina: request.isCatalina,
            isSierra: request.isSierra,
            needsCodesign: request.needsCodesign,
            requiresApplicationPathArg: request.requiresApplicationPathArg,
            requesterUID: request.requesterUID,
            linuxForceUnmount: true,
            windowsForceUnmount: request.windowsForceUnmount,
            windowsMountedSourcePath: request.windowsMountedSourcePath
        )
    }

    func showLinuxForceUnmountAlert(
        onForce: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "creator.unmount.alert.title", table: "Creator")
        alert.informativeText = linuxFlowContext?.isRawImageSelection == true
            ? String(localized: "creator.raw_image.unmount.alert.description", table: "Creator")
            : String(localized: "creator.linux.unmount.alert.description", table: "Creator")
        alert.addButton(withTitle: String(localized: "creator.action.cancel", table: "Creator"))
        alert.addButton(withTitle: String(localized: "creator.action.force_unmount", table: "Creator"))

        let completionHandler = { (response: NSApplication.ModalResponse) in
            if response == .alertSecondButtonReturn {
                onForce()
            } else {
                onCancel()
            }
        }

        if let window = NSApp.windows.first {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            let response = alert.runModal()
            completionHandler(response)
        }
    }

    func performLinuxUnmountDeclinedCleanupAndCancel() {
        helperCurrentStageKey = "cleanup_temp"
        helperStageTitleKey = HelperWorkflowLocalizationKeys.cleanupTempTitle
        helperStatusKey = HelperWorkflowLocalizationKeys.cleanupTempStatus
        helperWriteSpeedText = "- MB/s"

        withAnimation {
            isHelperWorking = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            performEmergencyCleanupIfNeeded(tempURL: tempWorkURL)
            DispatchQueue.main.async {
                isHelperWorking = false
                completeCancellationFlow()
            }
        }
    }
}
