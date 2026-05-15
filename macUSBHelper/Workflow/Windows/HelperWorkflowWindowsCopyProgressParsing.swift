import Foundation

extension HelperWorkflowExecutor {
    func extractWindowsCopyProgressPercent(from line: String) -> Double? {
        guard let totalBytes = windowsCopyStageTotalBytes, totalBytes > 0 else {
            return nil
        }

        let mode = windowsRsyncProgressMode ?? ""
        if mode == "progress2" {
            return parseWindowsRsyncProgress2Percent(line: line, totalBytes: totalBytes)
        }
        return parseWindowsRsyncLegacyPercent(line: line, totalBytes: totalBytes)
    }

    private func parseWindowsRsyncProgress2Percent(line: String, totalBytes: Int64) -> Double? {
        guard let progressRegex = try? NSRegularExpression(
            pattern: #"^\s*([0-9][0-9,\.]*[KMGTPkmgpt]?)\s+([0-9]{1,3})%\s+"#
        ) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = progressRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let bytesRange = Range(match.range(at: 1), in: line),
              let copiedBytes = parseRsyncProgressTokenToBytes(String(line[bytesRange])) else {
            return nil
        }

        let computed = (Double(copiedBytes) / Double(totalBytes)) * 100.0
        return min(max(computed, 0), 99)
    }

    private func parseWindowsRsyncLegacyPercent(line: String, totalBytes: Int64) -> Double? {
        if let filePath = parseWindowsLegacyRsyncFilePathLine(line: line) {
            windowsLegacyRsyncCurrentFilePath = filePath
            windowsLegacyRsyncCurrentFileSizeBytes = resolveWindowsSourceFileSize(forRsyncPath: filePath) ?? 0
            return nil
        }

        if let fileListPercent = parseWindowsLegacyRsyncFileListPercent(line: line) {
            return min(max(fileListPercent, 0), 99)
        }

        // Legacy rsync mode for Windows copy should track file-list progress
        // (`to-check`/`to-chk`) instead of per-file byte lines, to avoid jumps
        // when one large file is followed by many small files.
        _ = totalBytes
        return nil
    }

    private func parseWindowsLegacyRsyncFileListPercent(line: String) -> Double? {
        guard let progressRegex = try? NSRegularExpression(
            pattern: #"\((?:xfer#([0-9]+),\s*)?(?:to-check|to-chk|ir-chk)=([0-9]+)/([0-9]+)\)"#
        ) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = progressRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 4,
              let valueRange = Range(match.range(at: 2), in: line),
              let totalRange = Range(match.range(at: 3), in: line),
              let observedValue = Int(line[valueRange]),
              let totalCount = Int(line[totalRange]),
              totalCount > 0 else {
            return nil
        }

        let xferCount: Int? = {
            guard let xferRange = Range(match.range(at: 1), in: line) else { return nil }
            return Int(line[xferRange])
        }()

        if windowsLegacyRsyncToCheckUsesProcessedCount == nil,
           let xferCount {
            let processedCandidate = observedValue
            let remainingCandidate = max(0, totalCount - observedValue)
            let processedDistance = abs(processedCandidate - xferCount)
            let remainingDistance = abs(remainingCandidate - xferCount)
            windowsLegacyRsyncToCheckUsesProcessedCount = processedDistance <= remainingDistance
        }

        let usesProcessedCount = windowsLegacyRsyncToCheckUsesProcessedCount ?? true
        let processedCount = usesProcessedCount
            ? observedValue
            : max(0, totalCount - observedValue)

        return (Double(processedCount) / Double(totalCount)) * 100.0
    }

    private func parseWindowsLegacyRsyncFilePathLine(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered == "sending incremental file list"
            || lowered.hasPrefix("sent ")
            || lowered.hasPrefix("total size is ")
            || lowered.hasPrefix("speedup is ")
            || lowered.hasPrefix("number of files:")
            || lowered.hasPrefix("number of files transferred:")
            || lowered.hasPrefix("total transferred file size:")
            || lowered.hasPrefix("literal data:")
            || lowered.hasPrefix("matched data:")
            || lowered.hasPrefix("file list size:")
            || lowered.hasPrefix("file list generation time:")
            || lowered.hasPrefix("file list transfer time:")
            || lowered.hasPrefix("total bytes sent:")
            || lowered.hasPrefix("total bytes received:") {
            return nil
        }

        if line.range(of: #"^\s*[0-9][0-9,\.]*[KMGTPkmgpt]?\s+[0-9]{1,3}%\s+"#, options: .regularExpression) != nil {
            return nil
        }

        if trimmed == "." || trimmed == "./" {
            return nil
        }

        return trimmed
    }

    private func parseRsyncProgressTokenToBytes(_ token: String) -> Int64? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let suffix = trimmed.last, "KMGTPkmgpt".contains(suffix) {
            let numberPart = String(trimmed.dropLast()).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(numberPart), value.isFinite, value >= 0 else { return nil }

            let multiplier: Double
            switch suffix.uppercased() {
            case "K": multiplier = 1_000
            case "M": multiplier = 1_000_000
            case "G": multiplier = 1_000_000_000
            case "T": multiplier = 1_000_000_000_000
            case "P": multiplier = 1_000_000_000_000_000
            default: return nil
            }

            let bytes = value * multiplier
            guard bytes.isFinite, bytes >= 0 else { return nil }
            return Int64(bytes.rounded())
        }

        let digitsOnly = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard let bytes = Int64(digitsOnly), bytes >= 0 else {
            return nil
        }
        return bytes
    }

    private func resolveWindowsSourceFileSize(forRsyncPath path: String) -> Int64? {
        guard let sourceMountPath = windowsActiveSourceMountPath else { return nil }

        let sanitizedRelativePath: String
        if path.hasPrefix("./") {
            sanitizedRelativePath = String(path.dropFirst(2))
        } else {
            sanitizedRelativePath = path
        }

        guard !sanitizedRelativePath.isEmpty else { return nil }
        let candidate = URL(fileURLWithPath: sourceMountPath)
            .appendingPathComponent(sanitizedRelativePath)
            .path
        guard let attributes = try? fileManager.attributesOfItem(atPath: candidate),
              let sizeValue = attributes[.size] as? NSNumber else {
            return nil
        }

        return sizeValue.int64Value
    }
}
