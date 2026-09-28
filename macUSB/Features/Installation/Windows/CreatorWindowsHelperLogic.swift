import Foundation

extension UniversalInstallationView {
    func startWindowsCreationProcessWithHelper() {
        log(
            "Windows workflow starting: source=\(sourceAppURL.path), mountedSource=\(windowsMountedSourcePath ?? "none"), target=\(targetDrive?.device ?? "none"), bootMode=\(resolvedWindowsBootMode?.rawValue ?? "none").",
            category: "WindowsInstallFlow"
        )
        startCreationProcessWithHelper()
    }

    func prepareWindowsHelperWorkflowRequest(for drive: USBDrive) -> HelperWorkflowRequestPayload {
        let helperTargetBSDName = resolveHelperTargetBSDName(for: drive)
        let requesterUID = Int(getuid())
        let targetLabel = windowsTargetVolumeLabel()
        let helperBootMode = resolvedWindowsBootMode.map { mode in
            switch mode {
            case .bios:
                return HelperWindowsBootMode.bios
            case .uefi:
                return HelperWindowsBootMode.uefi
            }
        }

        let autounattendPayload = CreatorWindowsAutounattendWindowsVersion.detected(
            from: systemName,
            architecture: windowsArchitecture
        ) != nil
            ? windowsAutounattendConfiguration.helperPayload()
            : nil

        log(
            "Windows helper request prepared: source=\(sourceAppURL.path), mountedSource=\(windowsMountedSourcePath ?? "none"), targetBSD=\(helperTargetBSDName), label=\(targetLabel), bootMode=\(helperBootMode?.rawValue ?? "none"), splitWIM=\(windowsWillSplitWim), generatedAnswerFile=\(autounattendPayload != nil), sourceAnswerFileDecision=\(windowsAutounattendConfiguration.existingFileDecision?.rawValue ?? "none").",
            category: "WindowsInstallFlow"
        )
        if autounattendPayload != nil {
            let options = windowsAutounattendConfiguration
            log(
                "Windows answer-file options: hardwareBypass=\(options.skipHardwareRequirements), macLocale=\(options.useMacLanguageAndRegion), preventDeviceEncryption=\(options.preventDeviceEncryption), disableDataCollection=\(options.disableDataCollection), skipWirelessSetup=\(options.skipWirelessSetup), skipMicrosoftAccount=\(options.skipMicrosoftAccountRequirement), createLocalAccount=\(options.createLocalAccount).",
                category: "WindowsInstallFlow"
            )
        }

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
            windowsMountedSourcePath: windowsMountedSourcePath,
            windowsAutounattendConfiguration: autounattendPayload,
            windowsBootMode: helperBootMode
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
