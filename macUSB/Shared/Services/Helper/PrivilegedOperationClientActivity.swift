import Foundation

extension PrivilegedOperationClient {
    func registerWorkflowActivityLocked(workflowID: String) {
        workflowActivityTokens[workflowID]?.finish()
        workflowActivityTokens[workflowID] = AppActiveOperationRegistry.shared.begin(
            kind: .helperActivity,
            context: "helper_usb_workflow:\(workflowID)"
        )
    }

    func registerDownloaderAssemblyActivityLocked(workflowID: String) {
        downloaderAssemblyActivityTokens[workflowID]?.finish()
        downloaderAssemblyActivityTokens[workflowID] = AppActiveOperationRegistry.shared.begin(
            kind: .helperActivity,
            context: "helper_downloader_assembly:\(workflowID)"
        )
    }

    func removeAllActivityTokensLocked() -> [AppActiveOperationToken] {
        let tokens = Array(workflowActivityTokens.values)
            + Array(downloaderAssemblyActivityTokens.values)
        workflowActivityTokens.removeAll()
        downloaderAssemblyActivityTokens.removeAll()
        return tokens
    }

    func finishAllWorkflowActivityAfterDecodeFailure() {
        lock.lock()
        let tokens = Array(workflowActivityTokens.values)
        workflowActivityTokens.removeAll()
        lock.unlock()
        tokens.forEach { $0.finish() }
    }

    func finishAllDownloaderAssemblyActivityAfterDecodeFailure() {
        lock.lock()
        let tokens = Array(downloaderAssemblyActivityTokens.values)
        downloaderAssemblyActivityTokens.removeAll()
        lock.unlock()
        tokens.forEach { $0.finish() }
    }
}
