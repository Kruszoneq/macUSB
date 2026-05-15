import Foundation

extension HelperWorkflowExecutor {
    func extractWindowsWimSplitProgressPercent(from line: String) -> Double? {
        guard let progressRegex = try? NSRegularExpression(
            pattern: #"\(([0-9]{1,3})%\)\s+written\b"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = progressRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let percentRange = Range(match.range(at: 1), in: line),
              let percent = Double(line[percentRange]) else {
            return nil
        }

        return min(max(percent, 0), 100)
    }
}
