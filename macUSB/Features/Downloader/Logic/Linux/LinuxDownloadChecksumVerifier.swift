import Foundation
import CryptoKit

enum LinuxDownloadChecksumVerifier {
    /// Computes the SHA-256 of `fileURL` off the main actor, reporting progress as a fraction.
    static func sha256(
        of fileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let chunkSize = 8 * 1024 * 1024
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            let totalBytes = max(
                (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0,
                1
            )
            var hasher = SHA256()
            var processedBytes: Int64 = 0
            var lastReportedFraction = 0.0

            while true {
                try Task.checkCancellation()
                let chunk = try autoreleasepool {
                    try handle.read(upToCount: chunkSize) ?? Data()
                }
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                processedBytes += Int64(chunk.count)

                let fraction = min(1, Double(processedBytes) / Double(totalBytes))
                if fraction - lastReportedFraction >= 0.01 {
                    lastReportedFraction = fraction
                    progress(fraction)
                }
            }

            progress(1)
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
