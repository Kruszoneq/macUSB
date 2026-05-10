import Foundation

extension HelperWorkflowExecutor {
    func extractWindowsCopyProgressPercent(from line: String) -> Double? {
        guard let totalBytes = windowsCopyStageTotalBytes, totalBytes > 0 else {
            return nil
        }

        // Expected rsync progress2 row: "<bytes_done> <percent>% ..."
        guard let progressRegex = try? NSRegularExpression(
            pattern: #"^\s*([0-9][0-9,\.]*)\s+([0-9]{1,3})%\s+"#
        ) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = progressRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let bytesRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let rawBytes = String(line[bytesRange])
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")

        guard let copiedBytes = Int64(rawBytes), copiedBytes >= 0 else {
            return nil
        }

        let computed = (Double(copiedBytes) / Double(totalBytes)) * 100.0
        return min(max(computed, 0), 99)
    }
}
