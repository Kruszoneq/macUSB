import Foundation
import CryptoKit
import Darwin

struct AnalysisChecksumProgress: Sendable {
    let processedBytes: Int64
    let totalBytes: Int64

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0, Double(processedBytes) / Double(totalBytes)))
    }
}

enum AnalysisChecksumError: LocalizedError {
    case fileSizeUnavailable
    case openFailed(errno: Int32)
    case bufferAllocationFailed(code: Int32)
    case readFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .fileSizeUnavailable:
            return String(localized: "checksum.error.file_size_unavailable")
        case let .openFailed(errno):
            return String(
                format: String(localized: "checksum.error.open_failed"),
                String(cString: strerror(errno))
            )
        case let .bufferAllocationFailed(code):
            return String(
                format: String(localized: "checksum.error.buffer_allocation_failed"),
                code
            )
        case let .readFailed(errno):
            return String(
                format: String(localized: "checksum.error.read_failed"),
                String(cString: strerror(errno))
            )
        }
    }
}

struct AnalysisChecksumService: Sendable {
    private let bufferSize = 4 * 1_024 * 1_024
    private let bufferAlignment = 4_096

    nonisolated func calculateSHA256(
        for fileURL: URL,
        progressHandler: @escaping @Sendable (AnalysisChecksumProgress) -> Void
    ) async throws -> String {
        try Task.checkCancellation()

        let fileSize = try resolveFileSize(for: fileURL)
        await logStage("SHA-256 ISO - start")
        await logInfo("Rozpoczynam obliczanie SHA-256 dla ISO: \(fileURL.path)")
        await logInfo("Rozmiar pliku ISO: \(fileSize) bytes")

        let fd = open(fileURL.path, O_RDONLY)
        guard fd >= 0 else {
            throw AnalysisChecksumError.openFailed(errno: errno)
        }
        defer {
            close(fd)
        }

        await configureNoCacheIfAvailable(fileDescriptor: fd)

        var rawBuffer: UnsafeMutableRawPointer?
        let allocationResult = posix_memalign(&rawBuffer, bufferAlignment, bufferSize)
        guard allocationResult == 0, let buffer = rawBuffer else {
            throw AnalysisChecksumError.bufferAllocationFailed(code: allocationResult)
        }
        defer {
            free(buffer)
        }

        var hasher = SHA256()
        var processedBytes: Int64 = 0
        var nextLoggedPercent = 5
        progressHandler(AnalysisChecksumProgress(processedBytes: 0, totalBytes: fileSize))

        while true {
            try Task.checkCancellation()

            let bytesRead = readRetryingInterrupted(
                fileDescriptor: fd,
                buffer: buffer,
                count: bufferSize
            )

            if bytesRead < 0 {
                throw AnalysisChecksumError.readFailed(errno: errno)
            }

            if bytesRead == 0 {
                break
            }

            try Task.checkCancellation()

            let rawBufferPointer = UnsafeRawBufferPointer(start: buffer, count: bytesRead)
            hasher.update(bufferPointer: rawBufferPointer)
            processedBytes += Int64(bytesRead)

            let progress = AnalysisChecksumProgress(
                processedBytes: processedBytes,
                totalBytes: fileSize
            )
            progressHandler(progress)
            await logProgressIfNeeded(progress: progress, nextLoggedPercent: &nextLoggedPercent)
        }

        try Task.checkCancellation()

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        await logInfo("Zakończono obliczanie SHA-256 dla ISO: \(digest)")
        await logSeparator()
        return digest
    }

    nonisolated private func resolveFileSize(for fileURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw AnalysisChecksumError.fileSizeUnavailable
        }
        return size.int64Value
    }

    nonisolated private func configureNoCacheIfAvailable(fileDescriptor: Int32) async {
        #if os(macOS)
        let result = fcntl(fileDescriptor, F_NOCACHE, 1)
        if result == 0 {
            await logInfo("Włączono F_NOCACHE dla odczytu ISO.")
        } else {
            await logInfo("Nie udało się włączyć F_NOCACHE dla odczytu ISO: \(String(cString: strerror(errno)))")
        }
        #else
        await logInfo("F_NOCACHE jest niedostępne poza macOS.")
        #endif
    }

    nonisolated private func readRetryingInterrupted(
        fileDescriptor: Int32,
        buffer: UnsafeMutableRawPointer,
        count: Int
    ) -> Int {
        while true {
            let result = read(fileDescriptor, buffer, count)
            if result < 0, errno == EINTR {
                continue
            }
            return result
        }
    }

    nonisolated private func logProgressIfNeeded(
        progress: AnalysisChecksumProgress,
        nextLoggedPercent: inout Int
    ) async {
        guard progress.totalBytes > 0 else { return }

        let percent = min(100, Int((Double(progress.processedBytes) / Double(progress.totalBytes)) * 100))
        while percent >= nextLoggedPercent {
            await logInfo("Postęp obliczania SHA-256 ISO: \(nextLoggedPercent)%")
            nextLoggedPercent += 5
        }
    }

    nonisolated private func logStage(_ title: String) async {
        await MainActor.run {
            AppLogging.stage(title)
        }
    }

    nonisolated private func logInfo(_ message: String) async {
        await MainActor.run {
            AppLogging.info(message, category: "Checksum")
        }
    }

    nonisolated private func logSeparator() async {
        await MainActor.run {
            AppLogging.separator()
        }
    }
}
