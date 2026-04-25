import Foundation

extension HelperWorkflowExecutor {
    func mapLinuxRawCopyProgress(from line: String, stage: WorkflowStage) -> Double? {
        guard stage.key == "linux_raw_copy" else {
            return nil
        }

        guard let totalBytes = linuxSourceImageSizeBytes, totalBytes > 0,
              let transferredBytes = extractLinuxRawCopyTransferredBytes(from: line) else {
            return nil
        }

        let clampedRatio = min(max(Double(transferredBytes) / Double(totalBytes), 0), 1)
        let stagePercent = stage.startPercent + ((stage.endPercent - stage.startPercent) * clampedRatio)
        return max(stage.startPercent, min(stage.endPercent, stagePercent))
    }

    func extractLinuxRawCopyTransferredBytes(from line: String) -> Int64? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*([0-9]+)\s+bytes transferred"#, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }

        return Int64(line[range])
    }
}
