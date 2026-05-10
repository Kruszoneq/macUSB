import Foundation

extension UniversalInstallationView {
    func startWindowsCreationProcessWithHelper() {
        log(
            "WindowsInstallFlow: start workflow (source=\(sourceAppURL.path), mounted=\(windowsMountedSourcePath ?? "brak"), target=\(targetDrive?.device ?? "brak"))",
            category: "WindowsInstallFlow"
        )
        startCreationProcessWithHelper()
    }

    func prepareWindowsHelperWorkflowRequest(for drive: USBDrive) -> HelperWorkflowRequestPayload {
        let helperTargetBSDName = resolveHelperTargetBSDName(for: drive)
        let requesterUID = Int(getuid())
        let targetLabel = windowsTargetVolumeLabel()

        log(
            "WindowsInstallFlow: przygotowano helper request (source=\(sourceAppURL.path), mounted=\(windowsMountedSourcePath ?? "brak"), targetBSD=\(helperTargetBSDName), label=\(targetLabel))",
            category: "WindowsInstallFlow"
        )

        return HelperWorkflowRequestPayload(
            workflowKind: .windows,
            systemName: systemName,
            sourceAppPath: sourceAppURL.path,
            originalImagePath: originalImageURL?.path,
            tempWorkPath: tempWorkURL.path,
            targetVolumePath: drive.url.path,
            targetBSDName: helperTargetBSDName,
            targetLabel: targetLabel,
            needsPreformat: false,
            isCatalina: false,
            isSierra: false,
            needsCodesign: false,
            requiresApplicationPathArg: false,
            requesterUID: requesterUID,
            linuxForceUnmount: false,
            windowsForceUnmount: false,
            windowsMountedSourcePath: windowsMountedSourcePath
        )
    }

    func updateWindowsCopyProgressFromHelperPercent(stageKey: String, overallPercent: Double) {
        guard isWindowsWorkflow else { return }
        guard let percent = CreationProgressWindowsMapping.copyPercent(from: overallPercent, stageKey: stageKey) else {
            helperCopyProgressPercent = 0
            return
        }
        helperCopyProgressPercent = percent
    }
}
