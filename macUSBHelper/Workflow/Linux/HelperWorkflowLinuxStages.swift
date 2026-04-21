import Foundation

extension HelperWorkflowExecutor {
    func prepareLinuxWorkflowContext() throws -> PreparedWorkflowContext {
        guard fileManager.fileExists(atPath: request.sourceAppPath) else {
            throw HelperExecutionError.invalidRequest("Nie znaleziono źródłowego obrazu Linux.")
        }

        linuxSourceImageSizeBytes = resolveLinuxSourceImageSizeBytes()
        emitProgress(
            stageKey: "prepare_source",
            titleKey: HelperWorkflowLocalizationKeys.prepareSourceTitle,
            percent: latestPercent,
            statusKey: HelperWorkflowLocalizationKeys.prepareSourceStatus,
            logLine: "Linux helper workflow source: \(request.sourceAppPath), size=\(linuxSourceImageSizeBytes.map(String.init) ?? "?") bytes",
            shouldAdvancePercent: false
        )

        return PreparedWorkflowContext(sourcePath: request.sourceAppPath, postInstallSourceAppPath: nil)
    }

    func buildLinuxWorkflowStages(using context: PreparedWorkflowContext) throws -> [WorkflowStage] {
        let wholeDisk = try resolveLinuxTargetWholeDiskName()
        let rawTargetDevice = try resolveLinuxRawTargetDevicePath()

        emitProgress(
            stageKey: "prepare_source",
            titleKey: HelperWorkflowLocalizationKeys.prepareSourceTitle,
            percent: latestPercent,
            statusKey: HelperWorkflowLocalizationKeys.prepareSourceStatus,
            logLine: "Linux helper target resolution: requested=\(request.targetBSDName), wholeDisk=\(wholeDisk), rawDevice=\(rawTargetDevice)",
            shouldAdvancePercent: false
        )

        return [
            WorkflowStage(
                key: "linux_unmount_target",
                titleKey: HelperWorkflowLocalizationKeys.linuxUnmountTargetTitle,
                statusKey: HelperWorkflowLocalizationKeys.linuxUnmountTargetStatus,
                startPercent: 10,
                endPercent: 20,
                executable: "/usr/sbin/diskutil",
                arguments: ["unmountDisk", "/dev/\(wholeDisk)"],
                parseToolPercent: false
            ),
            WorkflowStage(
                key: "linux_raw_copy",
                titleKey: HelperWorkflowLocalizationKeys.linuxRawCopyTitle,
                statusKey: HelperWorkflowLocalizationKeys.linuxRawCopyStatus,
                startPercent: 20,
                endPercent: 98,
                executable: "/bin/dd",
                arguments: [
                    "if=\(context.sourcePath)",
                    "of=\(rawTargetDevice)",
                    "bs=4m",
                    "status=progress",
                    "conv=fsync"
                ],
                parseToolPercent: false
            )
        ]
    }
}
