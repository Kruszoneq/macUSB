import Foundation

extension HelperWorkflowExecutor {
    func runWindowsMacUSBootStage(_ stage: WorkflowStage) throws {
        do {
            try installWindowsMacUSBoot(stage)
        } catch let failure as HelperWorkflowWindowsMacUSBootFailure {
            emitProgress(
                stageKey: stage.key,
                titleKey: stage.titleKey,
                percent: latestPercent,
                statusKey: stage.statusKey,
                logLine: "macUSBoot installation failed: \(failure.diagnosticDescription)",
                shouldAdvancePercent: false
            )
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: failure.diagnosticDescription
            )
        } catch {
            let description = "macusboot_unknown: \(error.localizedDescription)"
            emitProgress(
                stageKey: stage.key,
                titleKey: stage.titleKey,
                percent: latestPercent,
                statusKey: stage.statusKey,
                logLine: "macUSBoot installation failed: \(description)",
                shouldAdvancePercent: false
            )
            throw HelperExecutionError.failed(stage: stage.key, exitCode: -1, description: description)
        }
    }

    private func installWindowsMacUSBoot(_ stage: WorkflowStage) throws {
        emitMacUSBootProgress(
            stage,
            statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootCheckingArtifact,
            logLine: "macUSBoot artifact validation started"
        )
        let artifact = try HelperWorkflowWindowsMacUSBootArtifactLoader.load()
        emitMacUSBootProgress(
            stage,
            statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootCheckingArtifact,
            logLine: "macUSBoot artifact validation completed: version=\(artifact.productVersion), file=\(artifact.binaryFileName), size=\(artifact.completeSize), sha256=\(artifact.completeSHA256)"
        )

        let wholeDisk = try extractWholeDiskName(from: request.targetBSDName)
        let rawPath = "/dev/r\(wholeDisk)"
        var mountGuard: HelperWorkflowWindowsMacUSBootMountGuard?
        var rawDevice: HelperWorkflowWindowsMacUSBootRawDevice?
        var shouldAttemptFinalMount = false
        var completed = false

        defer {
            if let rawDevice {
                let closed = rawDevice.close()
                emitMacUSBootProgress(
                    stage,
                    statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootVerifying,
                    logLine: "macUSBoot raw device closed: path=\(rawPath), result=\(closed ? "success" : "failure")"
                )
            }
            mountGuard?.stop(reason: completed ? "installation_success" : "installation_failure")
            if shouldAttemptFinalMount {
                macUSBootAttemptFinalMount(wholeDisk, stage: stage)
            }
        }

        let guardInstance = HelperWorkflowWindowsMacUSBootMountGuard(
            targetWholeDisk: wholeDisk,
            log: { message in
                self.emitMacUSBootProgress(
                    stage,
                    statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootUnmounting,
                    logLine: message
                )
            }
        )
        try guardInstance.start()
        mountGuard = guardInstance
        shouldAttemptFinalMount = true

        try macUSBootUnmountDisk(wholeDisk, stage: stage)
        try macUSBootConfirmDiskUnmounted(wholeDisk, stage: stage)

        let openedDevice = try HelperWorkflowWindowsMacUSBootRawDevice(path: rawPath)
        rawDevice = openedDevice
        emitMacUSBootProgress(
            stage,
            statusKey: HelperWorkflowLocalizationKeys.windowsInstallMacUSBootCheckingLayout,
            logLine: "macUSBoot raw device opened: path=\(rawPath), exclusive=yes, sectorSize=\(openedDevice.blockSize), sectors=\(openedDevice.blockCount)"
        )

        let transaction = HelperWorkflowWindowsMacUSBootTransaction(
            device: openedDevice,
            artifact: artifact,
            confirmUnmounted: {
                try self.macUSBootConfirmDiskUnmounted(wholeDisk, stage: stage)
            },
            report: { statusKey, logLine in
                self.emitMacUSBootProgress(stage, statusKey: statusKey, logLine: logLine)
            }
        )
        try transaction.run()
        completed = true
    }

    private func emitMacUSBootProgress(
        _ stage: WorkflowStage,
        statusKey: String,
        logLine: String
    ) {
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: statusKey,
            logLine: logLine,
            shouldAdvancePercent: false
        )
    }
}
