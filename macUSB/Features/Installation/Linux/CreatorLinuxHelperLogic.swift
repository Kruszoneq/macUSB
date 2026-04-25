import Foundation

extension UniversalInstallationView {
    func startLinuxCreationProcessWithHelper() {
        log("LinuxInstallFlow: start workflow (source=\(linuxFlowContext?.sourcePath ?? "brak"), target=\(targetDrive?.device ?? "brak"))", category: "LinuxInstallFlow")
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
        let requesterUID = Int(getuid())

        log(
            "LinuxInstallFlow: przygotowano helper request (source=\(linuxFlowContext.sourcePath), targetBSD=\(helperTargetBSDName), targetVolume=\(drive.url.path))",
            category: "LinuxInstallFlow"
        )

        return HelperWorkflowRequestPayload(
            workflowKind: .linux,
            systemName: systemName,
            sourceAppPath: linuxFlowContext.sourcePath,
            originalImagePath: nil,
            tempWorkPath: tempWorkURL.path,
            targetVolumePath: drive.url.path,
            targetBSDName: helperTargetBSDName,
            targetLabel: drive.url.lastPathComponent,
            needsPreformat: false,
            isCatalina: false,
            isSierra: false,
            needsCodesign: false,
            requiresApplicationPathArg: false,
            requesterUID: requesterUID,
            linuxForceUnmount: false
        )
    }
}
