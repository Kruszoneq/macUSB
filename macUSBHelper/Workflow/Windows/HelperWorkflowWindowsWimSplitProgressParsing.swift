import Foundation

extension HelperWorkflowExecutor {
    func extractWindowsWimSplitProgressPercent(from line: String) -> Double? {
        extractPercent(from: line)
    }
}
