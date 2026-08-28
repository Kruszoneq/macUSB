import Foundation

extension MontereyDownloadFlowModel {
    func verifyTemporaryDiskCapacity(requiredBytes: Int64) throws {
        let probeURL = FileManager.default.temporaryDirectory
        let minimumRequired = Int64((Double(requiredBytes) * 2.5).rounded(.up))

        AppLogging.info(
            "Preflight miejsca przed pobieraniem: sprawdzanie woluminu katalogu tymczasowego \(probeURL.path).",
            category: "Downloader"
        )

        let availableBytes: Int64
        do {
            let values = try probeURL.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            availableBytes = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        } catch {
            AppLogging.error(
                "Preflight miejsca przed pobieraniem: nie udało się odczytać dostępnego miejsca dla \(probeURL.path): \(error.localizedDescription)",
                category: "Downloader"
            )
            throw error
        }

        AppLogging.info(
            "Preflight miejsca przed pobieraniem [katalog tymczasowy]: wymagane=\(MacOSDownloadDiskSpaceDiagnostics.describe(minimumRequired)), dostępne=\(MacOSDownloadDiskSpaceDiagnostics.describe(availableBytes)), wynik=\(MacOSDownloadDiskSpaceDiagnostics.status(requiredBytes: minimumRequired, availableBytes: availableBytes)).",
            category: "Downloader"
        )
        guard availableBytes >= minimumRequired else {
            throw DownloadFailureReason.insufficientDiskSpace(
                requiredMinimumBytes: minimumRequired,
                availableBytes: availableBytes,
                installerBytes: requiredBytes
            )
        }
    }

    func prepareSessionDirectories() throws {
        let sessionID = UUID().uuidString.lowercased()
        let rootURL = downloaderSessionsRootURL()
            .appendingPathComponent(sessionID, isDirectory: true)
        let payloadURL = rootURL.appendingPathComponent("payload", isDirectory: true)
        let outputURL = rootURL.appendingPathComponent("output", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: payloadURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw DownloadFailureReason.sessionInitializationFailed(error.localizedDescription)
        }

        activeSessionID = sessionID
        activeSessionRootURL = rootURL
        activeSessionPayloadURL = payloadURL
        activeSessionOutputURL = outputURL
    }

    func shouldRetainSessionFilesForDebugMode() -> Bool {
        #if DEBUG
        return preserveDownloadedFilesInDebug
        #else
        return false
        #endif
    }

    func downloaderSessionsRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("macUSB_temp", isDirectory: true)
            .appendingPathComponent("downloads", isDirectory: true)
    }
}
