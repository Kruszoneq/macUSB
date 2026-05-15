import Foundation
import Darwin
import os.log

final class HelperWorkflowExecutor {
    let request: HelperWorkflowRequestPayload
    let workflowID: String
    let sendEvent: (HelperProgressEventPayload) -> Void

    let fileManager = FileManager.default
    var isCancelled = false
    let stateQueue = DispatchQueue(label: "macUSB.helper.executor.state")
    var activeProcess: Process?
    var latestPercent: Double = 0
    var lastStageOutputLine: String?
    var linuxSourceImageSizeBytes: Int64?
    var linuxMountGuard: HelperWorkflowLinuxMountGuard?
    var windowsMountedByHelper = false
    var windowsMountedImageDevice: String?
    var windowsActiveSourceMountPath: String?
    var windowsInstallWimPath: String?
    var windowsInstallWimRelativePath: String?
    var windowsInstallWimSizeBytes: Int64?
    var windowsShouldSplitWim = false
    var windowsHasInstallESD = false
    var windowsWimlibExecutablePath: String?
    var windowsPreparedTargetVolumePath: String?
    var windowsCopyStageTotalBytes: Int64?
    var windowsRsyncProgressMode: String?
    var windowsLegacyRsyncCurrentFilePath: String?
    var windowsLegacyRsyncCurrentFileSizeBytes: Int64 = 0
    var windowsLegacyRsyncCompletedBytes: Int64 = 0
    var windowsLegacyRsyncToCheckUsesProcessedCount: Bool?
    var currentStageKey: String?

    init(request: HelperWorkflowRequestPayload, workflowID: String, sendEvent: @escaping (HelperProgressEventPayload) -> Void) {
        self.request = request
        self.workflowID = workflowID
        self.sendEvent = sendEvent
    }

    func cancel() {
        stateQueue.sync {
            isCancelled = true
            guard let process = activeProcess, process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    func run() -> HelperWorkflowResultPayload {
        var linuxMountGuardReleaseReason: String?
        defer {
            stopLinuxMountGuardIfNeeded(reason: linuxMountGuardReleaseReason ?? "workflow_failed_pre_verify")
            attemptLinuxTargetMountAfterWorkflowIfNeeded()
        }

        do {
            let context = try prepareWorkflowContext()
            let stages = try buildStages(using: context)
            try startLinuxMountGuardIfNeeded(stages: stages)

            for stage in stages {
                if shouldSkipWindowsStage(stage) {
                    continue
                }
                currentStageKey = stage.key
                try throwIfCancelled()
                if stage.key == "catalina_copy" {
                    let transitionMessage = "Catalina: zakończono createinstallmedia, przejście do etapu ditto."
                    emit(stage: stage, percent: stage.startPercent, statusKey: stage.statusKey, logLine: transitionMessage)
                } else {
                    emit(stage: stage, percent: stage.startPercent, statusKey: stage.statusKey)
                }

                if stage.key == "linux_verify_write" {
                    linuxMountGuard?.markVerifyWindowActive()
                }

                try runStage(stage)
                emit(stage: stage, percent: stage.endPercent, statusKey: stage.statusKey)

                if stage.key == "linux_verify_write" {
                    linuxMountGuardReleaseReason = "verify_success"
                    stopLinuxMountGuardIfNeeded(reason: "verify_success")
                }
            }

            currentStageKey = nil
            runBestEffortTempCleanupStage()
            runFinalizeStage()

            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: true,
                failedStage: nil,
                errorCode: nil,
                errorMessage: nil,
                isUserCancelled: false
            )
        } catch HelperExecutionError.cancelled {
            linuxMountGuardReleaseReason = currentStageKey == "linux_verify_write"
                ? "verify_cancelled"
                : "workflow_failed_pre_verify"
            if linuxMountGuardReleaseReason == "verify_cancelled" {
                stopLinuxMountGuardIfNeeded(reason: "verify_cancelled")
            }
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "cancelled",
                errorCode: nil,
                errorMessage: "Operacja została anulowana przez użytkownika.",
                isUserCancelled: true
            )
        } catch HelperExecutionError.failed(let stage, let exitCode, let description) {
            linuxMountGuardReleaseReason = stage == "linux_verify_write"
                ? "verify_failed"
                : "workflow_failed_pre_verify"
            if linuxMountGuardReleaseReason == "verify_failed" {
                stopLinuxMountGuardIfNeeded(reason: "verify_failed")
            }
            if !shouldDeferCleanupForLinuxUnmountPrompt(failedStage: stage, description: description)
                && !shouldDeferCleanupForWindowsUnmountPrompt(failedStage: stage, description: description) {
                runBestEffortTempCleanupStage()
            }
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: stage,
                errorCode: Int(exitCode),
                errorMessage: description,
                isUserCancelled: false
            )
        } catch HelperExecutionError.invalidRequest(let message) {
            linuxMountGuardReleaseReason = "workflow_failed_pre_verify"
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "request",
                errorCode: nil,
                errorMessage: message,
                isUserCancelled: false
            )
        } catch {
            linuxMountGuardReleaseReason = currentStageKey == "linux_verify_write"
                ? "verify_failed"
                : "workflow_failed_pre_verify"
            if linuxMountGuardReleaseReason == "verify_failed" {
                stopLinuxMountGuardIfNeeded(reason: "verify_failed")
            }
            runBestEffortTempCleanupStage()
            return HelperWorkflowResultPayload(
                workflowID: workflowID,
                success: false,
                failedStage: "unknown",
                errorCode: nil,
                errorMessage: error.localizedDescription,
                isUserCancelled: false
            )
        }
    }

    private func startLinuxMountGuardIfNeeded(stages: [WorkflowStage]) throws {
        guard request.workflowKind == .linux else { return }
        guard stages.contains(where: { $0.key == "linux_unmount_target" }) else { return }

        let targetWholeDisk = try resolveLinuxTargetWholeDiskName()
        let guardInstance = HelperWorkflowLinuxMountGuard(
            targetWholeDisk: targetWholeDisk,
            log: { [weak self] message in
                guard let self else { return }
                self.emitProgress(
                    stageKey: "linux_unmount_target",
                    titleKey: HelperWorkflowLocalizationKeys.linuxUnmountTargetTitle,
                    percent: self.latestPercent,
                    statusKey: HelperWorkflowLocalizationKeys.linuxUnmountTargetStatus,
                    logLine: message,
                    shouldAdvancePercent: false
                )
            }
        )

        do {
            try guardInstance.start()
            linuxMountGuard = guardInstance
        } catch {
            throw HelperExecutionError.failed(
                stage: "linux_unmount_target",
                exitCode: -1,
                description: "Nie udało się aktywować blokady auto-mount Linux: \(error.localizedDescription)"
            )
        }
    }

    private func stopLinuxMountGuardIfNeeded(reason: String) {
        linuxMountGuard?.stop(reason: reason)
        linuxMountGuard = nil
    }

    private func attemptLinuxTargetMountAfterWorkflowIfNeeded() {
        guard request.workflowKind == .linux else { return }

        guard let targetWholeDisk = try? resolveLinuxTargetWholeDiskName() else {
            os_log("Linux post-mount attempt skipped: cannot resolve target whole disk", type: .default)
            return
        }

        let targetDevice = "/dev/\(targetWholeDisk)"
        let commandExecutable: String
        var commandArguments: [String]

        if let requesterUID = request.requesterUID, requesterUID > 0 {
            commandExecutable = "/bin/launchctl"
            commandArguments = ["asuser", "\(requesterUID)", "/usr/sbin/diskutil", "mountDisk", targetDevice]
        } else {
            commandExecutable = "/usr/sbin/diskutil"
            commandArguments = ["mountDisk", targetDevice]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: commandExecutable)
        process.arguments = commandArguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            os_log(
                "Linux post-mount attempt finished: target=%{public}@ exitCode=%{public}d",
                type: .default,
                targetDevice,
                process.terminationStatus
            )
        } catch {
            os_log(
                "Linux post-mount attempt failed to start: target=%{public}@ error=%{public}@",
                type: .error,
                targetDevice,
                error.localizedDescription
            )
        }
    }
}
