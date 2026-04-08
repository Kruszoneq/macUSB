import Foundation
import CryptoKit

extension MontereyDownloadFlowModel {
    private struct DownloadChecksumsManifest: Decodable {
        let schemaVersion: Int
        let systems: [DownloadChecksumRecord]
    }

    private struct DownloadChecksumRecord: Decodable {
        let family: String
        let name: String
        let version: String
        let sha256: String?
        let files: [DownloadChecksumFileRecord]?
    }

    private struct DownloadChecksumFileRecord: Decodable {
        let name: String
        let sha256: String
    }

    func runFileVerification(
        manifest: DownloadManifest,
        entry: MacOSInstallerEntry
    ) async throws {
        let usesModernVerificationProgress = shouldUseModernVerificationProgress(in: manifest)
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
            updateVerificationProgress(
                completedFiles: verifiedCount,
                totalCount: totalCount,
                currentFileFraction: usesModernVerificationProgress ? 0.0 : 0.02
            )

            guard let localURL = downloadedFileURLsByItemID[item.id] else {
                throw DownloadFailureReason.verificationFailed("Brak lokalnego pliku \(item.name)")
            }

            try verifyFileSize(for: localURL, expectedBytes: item.expectedSizeBytes, fileName: item.name)
            let shouldRunOldestOnlyVerification = shouldRunOldestDedicatedVerification(for: entry, fileURL: localURL)
            if shouldRunOldestOnlyVerification {
                try verifyOldestReferenceSHA256(for: localURL, entry: entry)
                try verifyEmbeddedPackageSignatureIfDiskImage(for: localURL, entry: entry)
            }
            let isPackage = localURL.pathExtension.lowercased() == "pkg"
            if isPackage {
                try verifyPackageSignature(for: localURL)
            }
            updateVerificationProgress(
                completedFiles: verifiedCount,
                totalCount: totalCount,
                currentFileFraction: usesModernVerificationProgress ? 0.20 : 0.15
            )

            if shouldRunOldestOnlyVerification {
                AppLogging.info(
                    "Weryfikacja \(verifyCurrentIndex)/\(verifyTotal): oldest-only checks zakonczone sukcesem dla \(item.name)",
                    category: "Downloader"
                )
                verifiedCount += 1
                verifyProgress = min(1.0, Double(verifiedCount) / totalCount)
                continue
            }

            if try await verifyIntegrityDataChunklistIfAvailable(
                for: localURL,
                item: item,
                progressHandler: { [weak self] fileFraction in
                    guard let self else { return }
                    self.updateVerificationProgress(
                        completedFiles: verifiedCount,
                        totalCount: totalCount,
                        currentFileFraction: usesModernVerificationProgress
                            ? (0.20 + (fileFraction * 0.80))
                            : (0.15 + (fileFraction * 0.65))
                    )
                }
            ) {
                AppLogging.info(
                    "Weryfikacja \(verifyCurrentIndex)/\(verifyTotal): zakonczona sukcesem przez IntegrityData dla \(item.name)",
                    category: "Downloader"
                )
                verifiedCount += 1
                verifyProgress = min(1.0, Double(verifiedCount) / totalCount)
                continue
            }

            if shouldRunHighSierraLegacySHA256Fallback(for: entry, item: item) {
                try verifyHighSierraReferenceSHA256(for: localURL, entry: entry, item: item)
                AppLogging.info(
                    "Weryfikacja \(verifyCurrentIndex)/\(verifyTotal): fallback SHA-256 dla High Sierra zakonczony sukcesem dla \(item.name)",
                    category: "Downloader"
                )
                verifiedCount += 1
                verifyProgress = min(1.0, Double(verifiedCount) / totalCount)
                continue
            }

            AppLogging.info(
                "IntegrityData: brak URL dla \(item.name), kontynuuje (rozmiar + podpis pakietu).",
                category: "Downloader"
            )
            AppLogging.info(
                "Weryfikacja \(verifyCurrentIndex)/\(verifyTotal): zakonczona bez IntegrityData dla \(item.name)",
                category: "Downloader"
            )

            verifiedCount += 1
            updateVerificationProgress(
                completedFiles: verifiedCount,
                totalCount: totalCount,
                currentFileFraction: 0
            )
            verifyProgress = min(1.0, Double(verifiedCount) / totalCount)
        }

        verifyProgress = 1.0
        completedStages.insert(.verifying)
    }

    private func updateVerificationProgress(
        completedFiles: Int,
        totalCount: Double,
        currentFileFraction: Double
    ) {
        let clampedFraction = min(max(currentFileFraction, 0), 1)
        let normalized = (Double(completedFiles) + clampedFraction) / max(totalCount, 1)
        verifyProgress = min(max(verifyProgress, normalized), 1.0)
    }

    private func shouldUseModernVerificationProgress(in manifest: DownloadManifest) -> Bool {
        let hasLegacyPackage = manifest.items.contains { item in
            item.name.caseInsensitiveCompare("InstallAssistantAuto.pkg") == .orderedSame
                || item.url.lastPathComponent.caseInsensitiveCompare("InstallAssistantAuto.pkg") == .orderedSame
        }
        if hasLegacyPackage {
            return false
        }

        let hasModernPackage = manifest.items.contains { item in
            item.name.caseInsensitiveCompare("InstallAssistant.pkg") == .orderedSame
                || item.url.lastPathComponent.caseInsensitiveCompare("InstallAssistant.pkg") == .orderedSame
        }
        return hasModernPackage
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

    private func verifyPackageSignature(
        for packageURL: URL,
        allowExpiredAppleCertificate: Bool = false
    ) throws {
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
            throw DownloadFailureReason.verificationFailed(
                "Nie udalo sie uruchomic pkgutil dla \(packageURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errors = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let details = [output, errors].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if task.terminationStatus != 0 {
            if allowExpiredAppleCertificate,
               isExpiredAppleSignedPackageSignature(details) {
                registerExpiredButTrustedAppleSignature(for: packageURL)
                AppLogging.info(
                    "Podpis pakietu zawiera wygasly certyfikat Apple, ale zostal zaakceptowany dla \(packageURL.lastPathComponent): \(details)",
                    category: "Downloader"
                )
                return
            }
            throw DownloadFailureReason.verificationFailed(
                "Podpis pakietu nie zostal potwierdzony przez pkgutil dla \(packageURL.lastPathComponent)\(details.isEmpty ? "" : ": \(details)")"
            )
        }

        AppLogging.info(
            "Podpis pakietu potwierdzony (pkgutil) dla \(packageURL.lastPathComponent)\(details.isEmpty ? "" : ": \(details)")",
            category: "Downloader"
        )
    }

    private func registerExpiredButTrustedAppleSignature(for packageURL: URL) {
        hasExpiredButTrustedAppleSignature = true
    }

    private func isExpiredAppleSignedPackageSignature(_ details: String) -> Bool {
        let normalized = details.lowercased()
        let expired = normalized.contains("signed by a certificate that has since expired")
        let appleChain = normalized.contains("software update")
            && normalized.contains("apple software update certification authority")
            && normalized.contains("apple root ca")
        return expired && appleChain
    }

    private func verifyEmbeddedPackageSignatureIfDiskImage(
        for diskImageURL: URL,
        entry: MacOSInstallerEntry
    ) throws {
        guard diskImageURL.pathExtension.lowercased() == "dmg" else {
            return
        }

        let mountURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("macusb_verify_\(UUID().uuidString)", isDirectory: true)

        var mounted = false
        defer {
            if mounted {
                let detachTask = Process()
                detachTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detachTask.arguments = ["detach", mountURL.path, "-force"]
                detachTask.standardOutput = Pipe()
                detachTask.standardError = Pipe()
                try? detachTask.run()
                detachTask.waitUntilExit()
            }
            try? FileManager.default.removeItem(at: mountURL)
        }

        do {
            try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        } catch {
            throw DownloadFailureReason.verificationFailed(
                "Nie udalo sie przygotowac punktu montowania dla \(diskImageURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        do {
            let attachTask = Process()
            attachTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            attachTask.arguments = [
                "attach", "-readonly", "-nobrowse",
                diskImageURL.path,
                "-mountpoint", mountURL.path
            ]

            let stdout = Pipe()
            let stderr = Pipe()
            attachTask.standardOutput = stdout
            attachTask.standardError = stderr
            try attachTask.run()
            attachTask.waitUntilExit()

            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errors = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let details = [output, errors].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard attachTask.terminationStatus == 0 else {
                throw DownloadFailureReason.verificationFailed(
                    "Nie udalo sie zamontowac obrazu \(diskImageURL.lastPathComponent)\(details.isEmpty ? "" : ": \(details)")"
                )
            }
            mounted = true
        } catch let error as DownloadFailureReason {
            throw error
        } catch {
            throw DownloadFailureReason.verificationFailed(
                "Nie udalo sie uruchomic hdiutil dla \(diskImageURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        let packageURLs = embeddedPackageCandidates(in: mountURL)
        guard let packageURL = packageURLs.first else {
            throw DownloadFailureReason.verificationFailed(
                "W obrazie \(diskImageURL.lastPathComponent) nie znaleziono pliku .pkg do weryfikacji podpisu"
            )
        }

        AppLogging.info(
            "Weryfikacja podpisu pakietu z obrazu dla \(entry.name) \(entry.version): \(packageURL.path)",
            category: "Downloader"
        )
        try verifyPackageSignature(
            for: packageURL,
            allowExpiredAppleCertificate: shouldAllowExpiredApplePackageSignature(for: entry)
        )
    }

    private func shouldRunOldestDedicatedVerification(
        for entry: MacOSInstallerEntry,
        fileURL: URL
    ) -> Bool {
        guard fileURL.pathExtension.lowercased() == "dmg" else {
            return false
        }
        let parts = entry.version.split(separator: ".")
        guard let major = parts.first.flatMap({ Int($0) }), major == 10 else {
            return false
        }
        let minor = parts.dropFirst().first.flatMap { Int($0) } ?? -1
        return (7...12).contains(minor)
    }

    private func verifyOldestReferenceSHA256(
        for fileURL: URL,
        entry: MacOSInstallerEntry
    ) throws {
        let expectedSHA = try expectedReferenceChecksumForOldest(entry: entry)
        let actualSHA = try computeFileSHA256Hex(for: fileURL)

        AppLogging.info(
            "Oldest SHA-256 verify \(entry.name) \(entry.version): expected=\(expectedSHA), actual=\(actualSHA)",
            category: "Downloader"
        )

        guard actualSHA.caseInsensitiveCompare(expectedSHA) == .orderedSame else {
            throw DownloadFailureReason.verificationFailed(
                "SHA-256 pliku \(fileURL.lastPathComponent) nie zgadza sie z referencja dla \(entry.name) \(entry.version)"
            )
        }
    }

    private func verifyHighSierraReferenceSHA256(
        for fileURL: URL,
        entry: MacOSInstallerEntry,
        item: DownloadManifestItem
    ) throws {
        let expectedSHA = try expectedReferenceChecksumForHighSierra(entry: entry, item: item)
        let actualSHA = try computeFileSHA256Hex(for: fileURL)

        AppLogging.info(
            "High Sierra SHA-256 fallback verify \(entry.name) \(entry.version) \(item.name): expected=\(expectedSHA), actual=\(actualSHA)",
            category: "Downloader"
        )

        guard actualSHA.caseInsensitiveCompare(expectedSHA) == .orderedSame else {
            throw DownloadFailureReason.verificationFailed(
                "SHA-256 pliku \(fileURL.lastPathComponent) nie zgadza sie z referencja dla \(entry.name) \(entry.version)"
            )
        }
    }

    private func shouldRunHighSierraLegacySHA256Fallback(
        for entry: MacOSInstallerEntry,
        item: DownloadManifestItem
    ) -> Bool {
        guard entry.version.hasPrefix("10.13") else {
            return false
        }

        let normalizedName = entry.name.lowercased()
        guard normalizedName.contains("high sierra") else {
            return false
        }

        let fileKey = normalizedHighSierraChecksumFileKey(for: item)
        return highSierraFallbackChecksumFileKeys.contains(fileKey)
    }

    private var highSierraFallbackChecksumFileKeys: Set<String> {
        [
            "installassistantauto.pkg",
            "recoveryhdmetadmg.pkg",
            "installesddmg.pkg"
        ]
    }

    private func normalizedHighSierraChecksumFileKey(for item: DownloadManifestItem) -> String {
        let candidateNames = [item.name, item.url.lastPathComponent]
        for candidate in candidateNames {
            let normalized = candidate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !normalized.isEmpty {
                return normalized
            }
        }
        return ""
    }

    private func expectedReferenceChecksumForOldest(entry: MacOSInstallerEntry) throws -> String {
        let manifest = try loadDownloadChecksumsManifest()
        let normalizedName = entry.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVersion = entry.version.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let match = manifest.systems.first(where: { record in
            record.family.caseInsensitiveCompare("oldest") == .orderedSame
                && record.version == normalizedVersion
                && record.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedName
        }) else {
            throw DownloadFailureReason.verificationFailed(
                "Brak referencyjnego SHA-256 dla \(entry.name) \(entry.version) w DownloadChecksums.json"
            )
        }

        guard let sha256 = match.sha256?.trimmingCharacters(in: .whitespacesAndNewlines), !sha256.isEmpty else {
            throw DownloadFailureReason.verificationFailed(
                "Brak referencyjnego SHA-256 dla \(entry.name) \(entry.version) w DownloadChecksums.json"
            )
        }

        return sha256.lowercased()
    }

    private func expectedReferenceChecksumForHighSierra(
        entry: MacOSInstallerEntry,
        item: DownloadManifestItem
    ) throws -> String {
        let manifest = try loadDownloadChecksumsManifest()
        let normalizedVersion = entry.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedFileKey = normalizedHighSierraChecksumFileKey(for: item)

        guard let highSierraRecord = manifest.systems.first(where: { record in
            record.family.caseInsensitiveCompare("legacy") == .orderedSame
                && record.version == normalizedVersion
                && record.name.lowercased().contains("high sierra")
        }) else {
            throw DownloadFailureReason.verificationFailed(
                "Brak referencyjnych SHA-256 dla \(entry.name) \(entry.version) w DownloadChecksums.json"
            )
        }

        guard let files = highSierraRecord.files, !files.isEmpty else {
            throw DownloadFailureReason.verificationFailed(
                "Brak listy plikow referencyjnych SHA-256 dla \(entry.name) \(entry.version) w DownloadChecksums.json"
            )
        }

        guard let fileRecord = files.first(where: { record in
            record.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == requestedFileKey
        }) else {
            throw DownloadFailureReason.verificationFailed(
                "Brak referencyjnego SHA-256 dla pliku \(item.name) (\(entry.name) \(entry.version)) w DownloadChecksums.json"
            )
        }

        return fileRecord.sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func loadDownloadChecksumsManifest() throws -> DownloadChecksumsManifest {
        guard let url = Bundle.main.url(
            forResource: "DownloadChecksums",
            withExtension: "json"
        ) else {
            throw DownloadFailureReason.verificationFailed(
                "Nie znaleziono pliku referencyjnego DownloadChecksums.json w bundle aplikacji"
            )
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DownloadChecksumsManifest.self, from: data)
    }

    private func shouldAllowExpiredApplePackageSignature(for entry: MacOSInstallerEntry) -> Bool {
        let normalizedName = entry.name.lowercased()
        guard normalizedName.contains("lion") else {
            return false
        }
        return entry.version.hasPrefix("10.7") || entry.version.hasPrefix("10.8")
    }

    private func embeddedPackageCandidates(in mountedImageURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: mountedImageURL,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [URL] = []
        for case let candidateURL as URL in enumerator {
            if candidateURL.pathExtension.lowercased() == "pkg" {
                candidates.append(candidateURL)
            }
        }

        return candidates.sorted { lhs, rhs in
            lhs.path.count < rhs.path.count
        }
    }

    private func verifyIntegrityDataChunklistIfAvailable(
        for fileURL: URL,
        item: DownloadManifestItem,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> Bool {
        guard let integrityDataURL = item.integrityDataURL else {
            AppLogging.info(
                "IntegrityData: brak URL dla \(item.name).",
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

        let chunkTable: IntegrityChunkTable
        do {
            chunkTable = try parseIntegrityChunkTable(from: integrityData, fileName: item.name)
            AppLogging.info(
                "IntegrityData: sparsowano \(chunkTable.totalChunks) chunkow dla \(item.name)",
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

        let totalChunkBytes = max(chunkTable.totalBytes, 1)
        let progressReportThresholdBytes = 8 * 1_048_576
        var processedChunkBytes = 0
        var lastReportedChunkBytes = 0
        var offset: UInt64 = 0
        for chunkIndex in 0..<chunkTable.totalChunks {
            try Task.checkCancellation()
            let chunk = try readIntegrityChunk(
                from: integrityData,
                table: chunkTable,
                index: chunkIndex,
                fileName: item.name
            )
            let computed = try computeSHA256ForIntegrityChunk(
                fileHandle: fileHandle,
                offset: offset,
                size: chunk.size
            ) { processedBytes in
                processedChunkBytes += processedBytes
                let shouldReport = (processedChunkBytes - lastReportedChunkBytes) >= progressReportThresholdBytes
                    || processedChunkBytes >= totalChunkBytes
                guard shouldReport else { return }
                lastReportedChunkBytes = processedChunkBytes
                progressHandler?(min(1.0, Double(processedChunkBytes) / Double(totalChunkBytes)))
            }
            if processedChunkBytes > lastReportedChunkBytes {
                lastReportedChunkBytes = processedChunkBytes
                progressHandler?(min(1.0, Double(processedChunkBytes) / Double(totalChunkBytes)))
            }
            if shouldLogIntegrityChunkStep(chunkIndex: chunkIndex, total: chunkTable.totalChunks) {
                AppLogging.info(
                    "IntegrityData chunk \(chunkIndex + 1)/\(chunkTable.totalChunks) \(item.name): expected=\(checksumPreview(chunk.sha256Hex)), actual=\(checksumPreview(hexString(computed))), size=\(chunk.size)",
                    category: "Downloader"
                )
            }
            guard computed == chunk.sha256 else {
                throw DownloadFailureReason.verificationFailed(
                    "Weryfikacja IntegrityData nie powiodla sie dla \(item.name) (chunk \(chunkIndex + 1)/\(chunkTable.totalChunks), expected=\(checksumPreview(chunk.sha256Hex)), actual=\(checksumPreview(hexString(computed))))"
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

    private func computeSHA256ForIntegrityChunk(
        fileHandle: FileHandle,
        offset: UInt64,
        size: Int,
        progressPerBytes: ((Int) -> Void)? = nil
    ) throws -> Data {
        try fileHandle.seek(toOffset: offset)
        var remaining = size
        var hasher = SHA256()
        let readBlockSize = 1_048_576

        while remaining > 0 {
            let blockSize = min(readBlockSize, remaining)
            var bytesRead = 0
            autoreleasepool {
                let data = fileHandle.readData(ofLength: blockSize)
                bytesRead = data.count
                if !data.isEmpty {
                    hasher.update(data: data)
                }
            }
            guard bytesRead > 0 else {
                throw DownloadFailureReason.verificationFailed(
                    "Nieoczekiwany koniec pliku podczas weryfikacji IntegrityData"
                )
            }
            remaining -= bytesRead
            progressPerBytes?(bytesRead)
        }

        return Data(hasher.finalize())
    }

    private func shouldLogIntegrityChunkStep(chunkIndex: Int, total: Int) -> Bool {
        if total <= 20 { return true }
        if chunkIndex < 5 || chunkIndex >= total - 5 { return true }
        return ((chunkIndex + 1) % 100) == 0
    }

    private struct IntegrityChunk {
        let size: Int
        let sha256: Data

        var sha256Hex: String {
            sha256.map { String(format: "%02X", $0) }.joined()
        }
    }

    private struct IntegrityChunkTable {
        let totalChunks: Int
        let chunkStart: Int
        let chunkEnd: Int
        let totalBytes: Int
    }

    private func parseIntegrityChunkTable(from data: Data, fileName: String) throws -> IntegrityChunkTable {
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

        guard totalChunks > 0 else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma niezgodna liczbe chunkow dla \(fileName)"
            )
        }
        guard totalChunks <= UInt64(Int.max / 36) else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma zbyt duza liczbe chunkow dla \(fileName)"
            )
        }

        let totalChunksInt = Int(totalChunks)
        let expectedChunkBytes = totalChunksInt * 36
        guard chunkEnd - chunkStart == expectedChunkBytes else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma niezgodna liczbe chunkow dla \(fileName)"
            )
        }

        var totalBytes = 0
        for index in 0..<totalChunksInt {
            let base = chunkStart + (index * 36)
            let size = Int(readUInt32LE(data, at: base))
            guard size > 0 else {
                throw DownloadFailureReason.verificationFailed(
                    "IntegrityData zawiera niepoprawny rozmiar chunka dla \(fileName)"
                )
            }
            guard totalBytes <= Int.max - size else {
                throw DownloadFailureReason.verificationFailed(
                    "IntegrityData ma niepoprawne sumaryczne rozmiary chunkow dla \(fileName)"
                )
            }
            totalBytes += size
        }

        return IntegrityChunkTable(
            totalChunks: totalChunksInt,
            chunkStart: chunkStart,
            chunkEnd: chunkEnd,
            totalBytes: totalBytes
        )
    }

    private func readIntegrityChunk(
        from data: Data,
        table: IntegrityChunkTable,
        index: Int,
        fileName: String
    ) throws -> IntegrityChunk {
        guard index >= 0, index < table.totalChunks else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma niepoprawny indeks chunka dla \(fileName)"
            )
        }

        let base = table.chunkStart + (index * 36)
        guard base >= table.chunkStart, base + 36 <= table.chunkEnd else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData ma niepoprawne offsety chunkow dla \(fileName)"
            )
        }

        let size = Int(readUInt32LE(data, at: base))
        guard size > 0 else {
            throw DownloadFailureReason.verificationFailed(
                "IntegrityData zawiera niepoprawny rozmiar chunka dla \(fileName)"
            )
        }

        let digestRange = (base + 4)..<(base + 36)
        return IntegrityChunk(size: size, sha256: Data(data[digestRange]))
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

    private func computeFileSHA256Hex(
        for fileURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let expectedSize = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber)?.int64Value ?? -1
        var processedBytes: Int64 = 0

        func updateDigestProgress(_ chunkSize: Int) {
            guard let progressHandler, expectedSize > 0 else { return }
            processedBytes += Int64(max(0, chunkSize))
            let progress = min(1.0, Double(processedBytes) / Double(expectedSize))
            progressHandler(progress)
        }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1_048_576)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            updateDigestProgress(data.count)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func checksumPreview(_ checksum: String) -> String {
        let trimmed = checksum.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 16 {
            return trimmed
        }
        return "\(trimmed.prefix(8))...\(trimmed.suffix(8))"
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

}
