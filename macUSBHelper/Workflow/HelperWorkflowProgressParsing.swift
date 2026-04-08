import Foundation

extension HelperWorkflowExecutor {
    func handleOutputLine(_ rawLine: String, stage: WorkflowStage) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        lastStageOutputLine = line

        var percent = latestPercent
        if stage.key == "ppc_restore", let mapped = mapPPCProgress(from: line) {
            percent = max(percent, mapped)
        } else if stage.parseToolPercent, let parsed = extractToolPercent(from: line, stageKey: stage.key) {
            let clamped = max(0, min(parsed, 100))
            let mapped = stage.startPercent + ((stage.endPercent - stage.startPercent) * (clamped / 100.0))
            percent = max(percent, mapped)
        }

        emit(stage: stage, percent: percent, statusKey: stage.statusKey, logLine: line)
    }
    func extractToolPercent(from line: String, stageKey: String) -> Double? {
        if stageKey == "createinstallmedia" {
            let lowered = line.lowercased()
            if lowered.contains("erasing disk") {
                return nil
            }
        }

        return extractPercent(from: line)
    }
    func mapPPCProgress(from line: String) -> Double? {
        let lowered = line.lowercased()

        if lowered.contains("validating target...done") {
            return 25
        }

        if lowered.contains("validating sizes...done") {
            return 30
        }

        guard let parsedPercent = extractPercent(from: line) else {
            return nil
        }

        let clamped = max(0, min(parsedPercent, 100))
        if clamped >= 100 {
            return 100
        }

        guard clamped >= 10 else {
            return nil
        }

        let tenStep = Int(clamped / 10.0)
        let boundedStep = min(max(tenStep, 1), 9)
        return 35 + (Double(boundedStep - 1) * 8)
    }
    func emit(stage: WorkflowStage, percent: Double, statusKey: String, logLine: String? = nil) {
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: percent,
            statusKey: statusKey,
            logLine: logLine
        )
    }
    func emitProgress(
        stageKey: String,
        titleKey: String,
        percent: Double,
        statusKey: String,
        logLine: String? = nil,
        shouldAdvancePercent: Bool = true
    ) {
        let clampedPercent = min(max(percent, 0), 100)
        let effectivePercent: Double
        if shouldAdvancePercent {
            latestPercent = max(latestPercent, clampedPercent)
            effectivePercent = latestPercent
        } else {
            effectivePercent = clampedPercent
        }

        let event = HelperProgressEventPayload(
            workflowID: workflowID,
            stageKey: stageKey,
            stageTitleKey: titleKey,
            percent: effectivePercent,
            statusKey: statusKey,
            logLine: logLine,
            timestamp: Date()
        )
        sendEvent(event)
    }
    func drainBufferedOutputLines(from buffer: inout Data, handleLine: (String) -> Void) {
        while let separatorIndex = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer.subdata(in: buffer.startIndex..<separatorIndex)
            var removeUpperBound = separatorIndex + 1

            if buffer[separatorIndex] == 0x0D,
               removeUpperBound < buffer.endIndex,
               buffer[removeUpperBound] == 0x0A {
                removeUpperBound += 1
            }

            buffer.removeSubrange(buffer.startIndex..<removeUpperBound)

            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else {
                continue
            }

            handleLine(line)
        }
    }
    func extractPercent(from line: String) -> Double? {
        if let standardPercent = extractLastNumberToken(
            from: line,
            pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)%"#
        ) {
            return standardPercent
        }

        // asr restore can emit progress in dotted form: "....10....20...."
        return extractLastNumberToken(
            from: line,
            pattern: #"\.{2,}\s*([0-9]{1,3})(?=\s*\.{2,})"#
        )
    }
    func extractLastNumberToken(from line: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: line.utf16.count)
        let matches = regex.matches(in: line, options: [], range: range)
        guard let lastMatch = matches.last,
              lastMatch.numberOfRanges > 1,
              let valueRange = Range(lastMatch.range(at: 1), in: line) else {
            return nil
        }

        let rawValue = String(line[valueRange]).replacingOccurrences(of: ",", with: ".")
        return Double(rawValue)
    }
}
