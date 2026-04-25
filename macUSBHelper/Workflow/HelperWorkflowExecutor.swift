import Foundation
import Darwin

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
        do {
            let context = try prepareWorkflowContext()
            let stages = try buildStages(using: context)
            for stage in stages {
                try throwIfCancelled()
                if stage.key == "catalina_copy" {
                    let transitionMessage = "Catalina: zakończono createinstallmedia, przejście do etapu ditto."
                    emit(stage: stage, percent: stage.startPercent, statusKey: stage.statusKey, logLine: transitionMessage)
                } else {
                    emit(stage: stage, percent: stage.startPercent, statusKey: stage.statusKey)
                }
                try runStage(stage)
                emit(stage: stage, percent: stage.endPercent, statusKey: stage.statusKey)
            }

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
            if !shouldDeferCleanupForLinuxUnmountPrompt(failedStage: stage, description: description) {
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
}
