import Foundation
import AppKit
import SwiftUI

extension UniversalInstallationView {
    func shouldPromptWindowsForceUnmountAlert(for result: HelperWorkflowResultPayload) -> Bool {
        guard isWindowsWorkflow else { return false }
        guard !result.success else { return false }
        guard result.failedStage == "windows_prepare_target" else { return false }
        guard let message = result.errorMessage?.lowercased() else { return false }
        return message.contains("windows_unmount_force_prompt")
            || message.contains("windows_unmount_busy_prompt")
    }

    func makeWindowsForceUnmountRequest(from request: HelperWorkflowRequestPayload) -> HelperWorkflowRequestPayload {
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
            linuxForceUnmount: request.linuxForceUnmount,
            windowsForceUnmount: true,
            windowsMountedSourcePath: request.windowsMountedSourcePath
        )
    }

    func showWindowsForceUnmountAlert(
        onForce: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Nie można odmontować nośnika USB")
        alert.informativeText = String(localized: "Wybrany nośnik jest używany przez inną aplikację. Aby kontynuować tworzenie nośnika Windows, macUSB może wymusić odmontowanie urządzenia. Niezapisane dane na tym nośniku mogą zostać utracone. Czy chcesz wymusić odmontowanie?")
        alert.addButton(withTitle: String(localized: "Anuluj"))
        alert.addButton(withTitle: String(localized: "Wymuś odmontowanie"))

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

    func performWindowsUnmountDeclinedCleanupAndCancel() {
        helperCurrentStageKey = "windows_cleanup_temp"
        helperStageTitleKey = HelperWorkflowLocalizationKeys.windowsCleanupTempTitle
        helperStatusKey = HelperWorkflowLocalizationKeys.windowsCleanupTempStatus
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
