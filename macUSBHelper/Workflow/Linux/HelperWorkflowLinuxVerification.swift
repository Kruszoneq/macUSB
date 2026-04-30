import Foundation
import CryptoKit

extension HelperWorkflowExecutor {
    private static let linuxVerificationChunkBytes = 1_048_576

    func runLinuxVerifyWriteStage(_ stage: WorkflowStage) throws {
        guard let rawDevicePath = stage.arguments.first, !rawDevicePath.isEmpty else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się ustalić urządzenia do weryfikacji zapisu Linux."
            )
        }

        let sourcePath = request.sourceAppPath
        guard fileManager.fileExists(atPath: sourcePath) else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie znaleziono źródłowego obrazu Linux do weryfikacji."
            )
        }

        guard let sourceBytes = resolveLinuxSourceImageSizeBytes(), sourceBytes > 0 else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się ustalić rozmiaru źródłowego obrazu Linux do weryfikacji."
            )
        }

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Linux verify: start (source=\(sourcePath), device=\(rawDevicePath), bytes=\(sourceBytes))",
            shouldAdvancePercent: false
        )

        let sourceHash = try computeSHA256Hex(atPath: sourcePath, byteLimit: sourceBytes, stage: stage, label: "source")
        let deviceHash = try computeSHA256Hex(atPath: rawDevicePath, byteLimit: sourceBytes, stage: stage, label: "device")

        let sourcePreview = checksumPreview(sourceHash)
        let devicePreview = checksumPreview(deviceHash)
        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Linux verify: source=\(sourcePreview), device=\(devicePreview)",
            shouldAdvancePercent: false
        )

        guard sourceHash.caseInsensitiveCompare(deviceHash) == .orderedSame else {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: 3,
                description: "Weryfikacja zapisu Linux nie powiodła się: dane na nośniku USB różnią się od obrazu źródłowego."
            )
        }

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Linux verify: completed successfully",
            shouldAdvancePercent: false
        )
    }

    private func computeSHA256Hex(
        atPath path: String,
        byteLimit: Int64,
        stage: WorkflowStage,
        label: String
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: path)
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Nie udało się otworzyć \(label) do weryfikacji: \(error.localizedDescription)"
            )
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        var remaining = byteLimit
        while remaining > 0 {
            try throwIfCancelled()

            let nextRead = min(Int64(Self.linuxVerificationChunkBytes), remaining)
            var bytesRead = 0
            autoreleasepool {
                let data = handle.readData(ofLength: Int(nextRead))
                bytesRead = data.count
                if !data.isEmpty {
                    hasher.update(data: data)
                }
            }

            guard bytesRead > 0 else {
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: 2,
                    description: "Weryfikacja zapisu Linux nie powiodła się: nieoczekiwany koniec danych \(label)."
                )
            }

            remaining -= Int64(bytesRead)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func checksumPreview(_ checksum: String) -> String {
        let trimmed = checksum.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 16 {
            return trimmed
        }
        return "\(trimmed.prefix(8))...\(trimmed.suffix(8))"
    }
}
