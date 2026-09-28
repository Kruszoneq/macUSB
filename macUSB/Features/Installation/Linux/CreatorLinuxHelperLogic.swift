import Foundation

extension UniversalInstallationView {
    func startLinuxCreationProcessWithHelper() {
        log("Raw-copy workflow starting: source=\(linuxFlowContext?.sourcePath ?? "none"), target=\(targetDrive?.device ?? "none"), manualRawImage=\(linuxFlowContext?.isRawImageSelection == true).", category: "LinuxInstallFlow")
        startCreationProcessWithHelper()
    }

    func prepareLinuxHelperWorkflowRequest(for drive: USBDrive) throws -> HelperWorkflowRequestPayload {
        guard let linuxFlowContext else {
            throw NSError(
                domain: "macUSB",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Brak źródła obrazu Linux do utworzenia nośnika USB.")]
            )
        }

        let helperTargetBSDName = resolveHelperTargetBSDName(for: drive)
        let helperTargetVolumePath = "/dev/\(helperTargetBSDName)"
        let requesterUID = Int(getuid())

        log(
            "Raw-copy helper request prepared: source=\(linuxFlowContext.sourcePath), targetBSD=\(helperTargetBSDName), targetVolume=\(helperTargetVolumePath).",
            category: "LinuxInstallFlow"
        )

        return HelperWorkflowRequestPayload(
            workflowKind: .linux,
            systemName: systemName,
            sourceAppPath: linuxFlowContext.sourcePath,
            originalImagePath: nil,
            tempWorkPath: tempWorkURL.path,
            targetVolumePath: helperTargetVolumePath,
            targetBSDName: helperTargetBSDName,
            targetLabel: drive.url.lastPathComponent,
            needsPreformat: false,
            isCatalina: false,
            isSierra: false,
            needsCodesign: false,
            requiresApplicationPathArg: false,
            requesterUID: requesterUID,
            linuxForceUnmount: false,
            windowsForceUnmount: false,
            windowsMountedSourcePath: nil
        )
    }
}
