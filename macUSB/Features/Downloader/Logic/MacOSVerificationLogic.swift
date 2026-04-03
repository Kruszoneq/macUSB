import Foundation
import CryptoKit

extension MontereyDownloadFlowModel {
    private enum DigestVerificationFailure: LocalizedError {
        case mismatch(fileName: String, algorithm: String, expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case let .mismatch(fileName, _, _, _):
                return "Suma kontrolna pliku \(fileName) jest niepoprawna"
            }
        }
    }

    func runFileVerification(manifest: DownloadManifest) async throws {
        currentStage = .verifying
        verifyCurrentIndex = 0
        verifyTotal = manifest.items.count
        verifyProgress = 0

        var verifiedCount = 0
        let totalCount = Double(max(manifest.items.count, 1))

        for (index, item) in manifest.items.enumerated() {
            try Task.checkCancellation()

            verifyCurrentIndex = index + 1
            verifyFileName = item.name
            AppLogging.info(
                "Weryfikacja \(verifyCurrentIndex)/\(verifyTotal): start dla \(item.name)",
                category: "Downloader"
            )

            guard let localURL = downloadedFileURLsByItemID[item.id] else {
                throw DownloadFailureReason.verificationFailed("Brak lokalnego pliku \(item.name)")
            }

            try verifyFileSize(for: localURL, expectedBytes: item.expectedSizeBytes, fileName: item.name)
            let isPackage = localURL.pathExtension.lowercased() == "pkg"
            let signatureVerified = isPackage ? verifyPackageSignatureIfPossible(for: localURL) : false

            if try await verifyIntegrityDataChunklistIfAvailable(for: localURL, item: item) {
                try logSHA256VerificationDetails(for: localURL, item: item)
                AppLogging.info(
                    "Weryfikacja \(verifyCurrentIndex)/\(verifyTotal): zakonczona sukcesem przez IntegrityData dla \(item.name)",
                    category: "Downloader"
                )
                verifiedCount += 1
                verifyProgress = min(1.0, Double(verifiedCount) / totalCount)
                continue
            }

            if isPackage {
                AppLogging.info(
                    "Brak IntegrityData dla \(item.name). Uzywam fallback digest.",
                    category: "Downloader"
                )
            }
            do {
                try verifyDigestIfNeeded(for: localURL, item: item)
            } catch let digestFailure as DigestVerificationFailure {
                if isPackage {
                    guard signatureVerified else {
                        throw DownloadFailureReason.verificationFailed(
                            digestFailure.errorDescription ?? "Suma kontrolna pliku \(item.name) jest niepoprawna"
                        )
                    }
                    AppLogging.info("Checksum mismatch dla \(item.name) zaakceptowany po fallbacku podpisu pakietu.", category: "Downloader")
                } else {
                    throw DownloadFailureReason.verificationFailed(
                        digestFailure.errorDescription ?? "Suma kontrolna pliku \(item.name) jest niepoprawna"
                    )
                }
            }

            try logSHA256VerificationDetails(for: localURL, item: item)
            AppLogging.info(
                "Weryfikacja \(verifyCurrentIndex)/\(verifyTotal): zakonczona sukcesem fallback digest dla \(item.name)",
                category: "Downloader"
            )

            verifiedCount += 1
            verifyProgress = min(1.0, Double(verifiedCount) / totalCount)
        }

        verifyProgress = 1.0
        completedStages.insert(.verifying)
    }

    private func verifyFileSize(for fileURL: URL, expectedBytes: Int64, fileName: String) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DownloadFailureReason.verificationFailed("Nie znaleziono pobranego pliku \(fileName)")
        }

        let currentSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?
            .int64Value ?? -1
        AppLogging.info(
            "Sprawdzanie rozmiaru \(fileName): expected=\(expectedBytes), actual=\(currentSize)",
            category: "Downloader"
        )
        guard currentSize == expectedBytes else {
            throw DownloadFailureReason.verificationFailed(
                "Rozmiar pliku \(fileName) jest niepoprawny (\(currentSize) != \(expectedBytes))"
            )
        }
    }

    private func verifyDigestIfNeeded(for fileURL: URL, item: DownloadManifestItem) throws {
        guard let expectedDigestRaw = item.expectedDigest?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedDigestRaw.isEmpty
        else {
            return
        }

        let expectedHex = normalizeExpectedDigestToHex(expectedDigestRaw)
        let algorithm = resolvedDigestAlgorithm(
            explicitAlgorithm: item.digestAlgorithm,
            rawDigest: expectedDigestRaw,
            normalizedHexDigest: expectedHex
        )
        let computedHex = try computeFileDigestHex(for: fileURL, algorithm: algorithm)
        AppLogging.info(
            "Digest verify \(item.name): alg=\(algorithmLabel(algorithm)), expected=\(checksumPreview(expectedHex)), actual=\(checksumPreview(computedHex))",
            category: "Downloader"
        )

        guard computedHex.caseInsensitiveCompare(expectedHex) == .orderedSame else {
            let algorithmText = algorithmLabel(algorithm)
            AppLogging.error(
                "Mismatch checksum dla \(item.name): alg=\(algorithmText), expected=\(checksumPreview(expectedHex)), actual=\(checksumPreview(computedHex))",
                category: "Downloader"
            )
            throw DigestVerificationFailure.mismatch(
                fileName: item.name,
                algorithm: algorithmText,
                expected: expectedHex,
                actual: computedHex
            )
        }
    }

    private func verifyPackageSignatureIfPossible(for packageURL: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        task.arguments = ["--check-signature", packageURL.path]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            AppLogging.error(
                "Nie udalo sie uruchomic pkgutil dla \(packageURL.lastPathComponent): \(error.localizedDescription)",
                category: "Downloader"
            )
            return false
        }

        if task.terminationStatus != 0 {
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errors = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let details = [output, errors].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            AppLogging.error(
                "Podpis pakietu nie zostal potwierdzony przez pkgutil dla \(packageURL.lastPathComponent)\(details.isEmpty ? "" : ": \(details)")",
                category: "Downloader"
            )
            return false
        }

        return true
    }

    private func verifyIntegrityDataChunklistIfAvailable(
        for fileURL: URL,
        item: DownloadManifestItem
    ) async throws -> Bool {
        guard let integrityDataURL = item.integrityDataURL else {
            AppLogging.info(
                "IntegrityData: brak URL dla \(item.name), przechodze na fallback digest.",
                category: "Downloader"
            )
            return false
        }
        guard isAppleIntegrityHost(integrityDataURL) else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityDataURL poza allowlista Apple dla \(item.name)"
            )
        }
        AppLogging.info(
            "IntegrityData: pobieram metadane dla \(item.name) z \(integrityDataURL.absoluteString)",
            category: "Downloader"
        )

        let integrityData: Data
        do {
            let (data, response) = try await URLSession.shared.data(from: integrityDataURL)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw DownloadFailureReason.verificationFailed(
                    "Nie udalo sie pobrac danych integralnosci dla \(item.name)"
                )
            }
            integrityData = data
            AppLogging.info(
                "IntegrityData: pobrano \(data.count) B dla \(item.name)",
                category: "Downloader"
            )
        } catch let error as DownloadFailureReason {
            throw error
        } catch {
            throw DownloadFailureReason.verificationFailed(
                "Blad pobierania IntegrityData dla \(item.name): \(error.localizedDescription)"
            )
        }

        let chunks: [IntegrityChunk]
        do {
            chunks = try parseIntegrityChunks(from: integrityData, fileName: item.name)
            AppLogging.info(
                "IntegrityData: sparsowano \(chunks.count) chunkow dla \(item.name)",
                category: "Downloader"
            )
        } catch let error as DownloadFailureReason {
            throw error
        } catch {
            throw DownloadFailureReason.verificationFailed(error.localizedDescription)
        }

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw DownloadFailureReason.verificationFailed(
                "Nie udalo sie otworzyc pliku do weryfikacji integralnosci \(item.name): \(error.localizedDescription)"
            )
        }
        defer { try? fileHandle.close() }

        var offset: UInt64 = 0
        for (chunkIndex, chunk) in chunks.enumerated() {
            try fileHandle.seek(toOffset: offset)
            let data = fileHandle.readData(ofLength: chunk.size)
            let computed = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().uppercased()
            if shouldLogIntegrityChunkStep(chunkIndex: chunkIndex, total: chunks.count) {
                AppLogging.info(
                    "IntegrityData chunk \(chunkIndex + 1)/\(chunks.count) \(item.name): expected=\(checksumPreview(chunk.sha256Hex)), actual=\(checksumPreview(computed)), size=\(chunk.size)",
                    category: "Downloader"
                )
            }
            guard computed == chunk.sha256Hex else {
                throw DownloadFailureReason.verificationFailed(
                    "Weryfikacja IntegrityData nie powiodla sie dla \(item.name) (chunk \(chunkIndex + 1)/\(chunks.count), expected=\(checksumPreview(chunk.sha256Hex)), actual=\(checksumPreview(computed)))"
                )
            }
            offset += UInt64(chunk.size)
        }
        AppLogging.info(
            "IntegrityData: weryfikacja chunklist zakonczona sukcesem dla \(item.name)",
            category: "Downloader"
        )

        return true
    }

    private func shouldLogIntegrityChunkStep(chunkIndex: Int, total: Int) -> Bool {
        if total <= 20 { return true }
        if chunkIndex < 5 || chunkIndex >= total - 5 { return true }
        return ((chunkIndex + 1) % 100) == 0
    }

    private struct IntegrityChunk {
        let size: Int
        let sha256Hex: String
    }

    private func parseIntegrityChunks(from data: Data, fileName: String) throws -> [IntegrityChunk] {
        guard data.count >= 36 else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma niepoprawny format dla \(fileName)"
            )
        }

        let magic = readUInt32LE(data, at: 0)
        let headerSize = readUInt32LE(data, at: 4)
        let chunkMethod = readUInt8(data, at: 9)
        let signatureMethod = readUInt8(data, at: 10)
        let totalChunks = readUInt64LE(data, at: 12)
        let chunksOffset = readUInt64LE(data, at: 20)
        let signatureOffset = readUInt64LE(data, at: 28)

        guard magic == 0x4C4B4E43, headerSize == 0x24, chunkMethod == 0x01, signatureMethod == 0x02 else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma nieobslugiwany naglowek dla \(fileName)"
            )
        }

        let chunkStart = Int(chunksOffset)
        let chunkEnd = Int(signatureOffset)
        guard chunkStart >= 0, chunkEnd <= data.count, chunkEnd >= chunkStart else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma niepoprawne offsety dla \(fileName)"
            )
        }

        let expectedChunkBytes = Int(totalChunks) * 36
        guard chunkEnd - chunkStart == expectedChunkBytes else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma niezgodna liczbe chunkow dla \(fileName)"
            )
        }

        var chunks: [IntegrityChunk] = []
        chunks.reserveCapacity(Int(totalChunks))

        for index in 0..<Int(totalChunks) {
            let base = chunkStart + (index * 36)
            let size = Int(readUInt32LE(data, at: base))
            let hashRange = (base + 4)..<(base + 36)
            let hashData = data.subdata(in: hashRange)
            let hashHex = hashData.map { String(format: "%02X", $0) }.joined()
            chunks.append(IntegrityChunk(size: size, sha256Hex: hashHex))
        }

        return chunks
    }

    private func readUInt8(_ data: Data, at offset: Int) -> UInt8 {
        data[data.index(data.startIndex, offsetBy: offset)]
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(readUInt8(data, at: offset))
        let b1 = UInt32(readUInt8(data, at: offset + 1)) << 8
        let b2 = UInt32(readUInt8(data, at: offset + 2)) << 16
        let b3 = UInt32(readUInt8(data, at: offset + 3)) << 24
        return b0 | b1 | b2 | b3
    }

    private func readUInt64LE(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(readUInt8(data, at: offset + i)) << UInt64(i * 8)
        }
        return value
    }

    private func isAppleIntegrityHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "swcdn.apple.com" || host == "swdist.apple.com" || host.hasSuffix(".apple.com")
    }

    private enum DigestAlgorithmKind {
        case sha1
        case sha256
    }

    private func resolvedDigestAlgorithm(
        explicitAlgorithm: String?,
        rawDigest: String,
        normalizedHexDigest: String
    ) -> DigestAlgorithmKind {
        if let explicitAlgorithm {
            let normalized = explicitAlgorithm.lowercased()
            if normalized.contains("sha256") {
                return .sha256
            }
            if normalized.contains("sha1") {
                return .sha1
            }
        }

        let hexCandidate = normalizedHexDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexCandidate.count == 64 {
            return .sha256
        }
        if hexCandidate.count == 40 {
            return .sha1
        }

        let base64Candidate = rawDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = Data(base64Encoded: base64Candidate) {
            switch decoded.count {
            case 32:
                return .sha256
            case 20:
                return .sha1
            default:
                break
            }
        }

        return .sha1
    }

    private func normalizeExpectedDigestToHex(_ digest: String) -> String {
        let trimmed = digest.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHex = trimmed.range(of: #"^[0-9a-fA-F]+$"#, options: .regularExpression) != nil
        if isHex {
            return trimmed.lowercased()
        }

        if let data = Data(base64Encoded: trimmed) {
            return data.map { String(format: "%02x", $0) }.joined()
        }

        return trimmed.lowercased()
    }

    private func computeFileDigestHex(for fileURL: URL, algorithm: DigestAlgorithmKind) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        switch algorithm {
        case .sha1:
            var hasher = Insecure.SHA1()
            while autoreleasepool(invoking: {
                let data = handle.readData(ofLength: 1_048_576)
                if data.isEmpty {
                    return false
                }
                hasher.update(data: data)
                return true
            }) {}
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()

        case .sha256:
            var hasher = SHA256()
            while autoreleasepool(invoking: {
                let data = handle.readData(ofLength: 1_048_576)
                if data.isEmpty {
                    return false
                }
                hasher.update(data: data)
                return true
            }) {}
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    private func algorithmLabel(_ algorithm: DigestAlgorithmKind) -> String {
        switch algorithm {
        case .sha1:
            return "sha1"
        case .sha256:
            return "sha256"
        }
    }

    private func checksumPreview(_ checksum: String) -> String {
        let trimmed = checksum.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 16 {
            return trimmed
        }
        return "\(trimmed.prefix(8))...\(trimmed.suffix(8))"
    }

    private func logSHA256VerificationDetails(for fileURL: URL, item: DownloadManifestItem) throws {
        let actualSHA256 = try computeFileDigestHex(for: fileURL, algorithm: .sha256)
        let expectedSHA256 = expectedSHA256FromManifest(for: item) ?? "N/A"
        AppLogging.info(
            "SHA-256 verify \(item.name): expected=\(expectedSHA256), actual=\(actualSHA256)",
            category: "Downloader"
        )
    }

    private func expectedSHA256FromManifest(for item: DownloadManifestItem) -> String? {
        guard let expectedDigestRaw = item.expectedDigest?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedDigestRaw.isEmpty
        else {
            return nil
        }

        let normalizedHex = normalizeExpectedDigestToHex(expectedDigestRaw)
        let algorithm = resolvedDigestAlgorithm(
            explicitAlgorithm: item.digestAlgorithm,
            rawDigest: expectedDigestRaw,
            normalizedHexDigest: normalizedHex
        )
        guard algorithm == .sha256 else {
            return nil
        }

        return normalizedHex.lowercased()
    }
}
