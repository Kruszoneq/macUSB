import Foundation

extension AnalysisLogic {
    func indexLinuxArchive(sourceURL: URL, timeout: TimeInterval = 10) -> LinuxArchiveIndex? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        task.arguments = ["-tf", sourceURL.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            self.logError("Nie udało się uruchomić bsdtar -tf: \(error.localizedDescription)")
            return nil
        }

        var stdoutBuffer = Data()
        var stderrBuffer = Data()
        let syncQueue = DispatchQueue(label: "LinuxArchiveReader.bsdtar")
        let stdoutEOF = DispatchSemaphore(value: 0)
        let stderrEOF = DispatchSemaphore(value: 0)

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                stdoutEOF.signal()
                return
            }
            syncQueue.sync {
                stdoutBuffer.append(chunk)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                stderrEOF.signal()
                return
            }
            syncQueue.sync {
                stderrBuffer.append(chunk)
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while task.isRunning {
            if Date() >= deadline {
                timedOut = true
                task.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        task.waitUntilExit()

        _ = stdoutEOF.wait(timeout: .now() + 1)
        _ = stderrEOF.wait(timeout: .now() + 1)

        let outputData = syncQueue.sync { stdoutBuffer }
        let errorData = syncQueue.sync { stderrBuffer }

        if timedOut {
            self.logError("bsdtar -tf timeout po \(Int(timeout)) s: \(sourceURL.lastPathComponent)")
            return nil
        }

        guard task.terminationStatus == 0 else {
            let stderrText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                self.logError("bsdtar -tf zakończył się błędem (kod \(task.terminationStatus)).")
            } else {
                self.logError("bsdtar -tf zakończył się błędem: \(stderrText)")
            }
            return nil
        }

        let rawList = String(decoding: outputData, as: UTF8.self)
        let entries = rawList
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var topLevelEntries: Set<String> = []
        var releaseCandidates: Set<String> = []

        for entry in entries {
            if entry == "." { continue }

            if let first = entry.split(separator: "/").first {
                let token = String(first)
                if !token.isEmpty {
                    topLevelEntries.insert(token)
                }
            }

            let components = entry.split(separator: "/")
            if components.count == 3, components[0] == "dists", components[2] == "Release" {
                releaseCandidates.insert(entry)
            }
        }

        return LinuxArchiveIndex(
            topLevelEntries: topLevelEntries,
            releaseCandidates: Array(releaseCandidates).sorted()
        )
    }

    func readLinuxArchiveTextFile(sourceURL: URL, relativePath: String, maxBytes: Int = 64_000, timeout: TimeInterval = 10) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        task.arguments = ["-xOf", sourceURL.path, relativePath]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            self.logError("Nie udało się uruchomić bsdtar -xOf: \(error.localizedDescription)")
            return nil
        }

        var stdoutBuffer = Data()
        var stderrBuffer = Data()
        let syncQueue = DispatchQueue(label: "LinuxArchiveReader.bsdtar.xOf")
        let stdoutEOF = DispatchSemaphore(value: 0)
        let stderrEOF = DispatchSemaphore(value: 0)

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                stdoutEOF.signal()
                return
            }
            syncQueue.sync {
                if stdoutBuffer.count < maxBytes {
                    let remaining = maxBytes - stdoutBuffer.count
                    stdoutBuffer.append(chunk.prefix(remaining))
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                stderrEOF.signal()
                return
            }
            syncQueue.sync {
                stderrBuffer.append(chunk)
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while task.isRunning {
            if Date() >= deadline {
                timedOut = true
                task.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        task.waitUntilExit()

        _ = stdoutEOF.wait(timeout: .now() + 1)
        _ = stderrEOF.wait(timeout: .now() + 1)

        let outputData = syncQueue.sync { stdoutBuffer }
        let errorData = syncQueue.sync { stderrBuffer }

        if timedOut {
            self.logError("bsdtar -xOf timeout po \(Int(timeout)) s dla: \(relativePath)")
            return nil
        }

        guard task.terminationStatus == 0 else {
            let stderrText = String(decoding: errorData, as: UTF8.self).lowercased()
            // Brak pliku w archiwum jest oczekiwany dla części heurystyk.
            if !stderrText.contains("not found in archive") {
                let clean = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty {
                    self.logError("bsdtar -xOf zakończył się błędem (kod \(task.terminationStatus)) dla: \(relativePath)")
                } else {
                    self.logError("bsdtar -xOf zakończył się błędem dla \(relativePath): \(clean)")
                }
            }
            return nil
        }

        guard !outputData.isEmpty else { return nil }
        return String(decoding: outputData, as: UTF8.self)
    }
}
