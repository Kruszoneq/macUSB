import Foundation

extension MontereyDownloadFlowModel {
    func downloadItemWithRetry(
        _ item: DownloadManifestItem,
        destinationURL: URL,
        maxAttempts: Int,
        progress: @escaping @MainActor (_ receivedBytes: Int64, _ expectedBytes: Int64) -> Void
    ) async throws -> Int64 {
        let attempts = max(1, maxAttempts)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await downloadItem(item, to: destinationURL, progress: progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if isOfflineDownloadError(error) {
                    AppLogging.error(
                        "Wykryto brak dostepu do internetu podczas pobierania \(item.name). Oczekiwanie na ponowne polaczenie (maksymalnie 60 sekund).",
                        category: "Downloader"
                    )
                    let recovered = try await waitForInternetReconnect(timeoutSeconds: internetReconnectTimeoutSeconds, probeURL: item.url)
                    if recovered {
                        networkWarningMessage = nil
                        downloadFileName = String(
                            format: String(localized: "Pobieranie pliku %@..."),
                            item.name
                        )
                        AppLogging.info(
                            "Polaczenie internetowe przywrocone. Wznawiam pobieranie \(item.name).",
                            category: "Downloader"
                        )
                        continue
                    }

                    throw DownloadFailureReason.downloadFailed(String(localized: "Brak dostępu do internetu przez ponad 1 minutę"))
                }

                lastError = error
                if attempt < attempts {
                    let delayNanoseconds = UInt64(500_000_000 * attempt * attempt)
                    AppLogging.info(
                        "Retry pobierania pliku \(item.name): proba \(attempt + 1)/\(attempts), opoznienie \(delayNanoseconds / 1_000_000) ms.",
                        category: "Downloader"
                    )
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    continue
                }
            }
        }

        throw lastError ?? DownloadFailureReason.downloadFailed(String(localized: "Nieznany błąd pobierania"))
    }

    func isOfflineDownloadError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        let message = (error as NSError).localizedDescription.lowercased()
        return message.contains("not connected to internet")
            || message.contains("network connection was lost")
            || message.contains("brak dostępu do internetu")
            || message.contains("brak dostepu do internetu")
            || message.contains("połączenie z siecią zostało utracone")
            || message.contains("polaczenie z siecia zostalo utracone")
    }

    func waitForInternetReconnect(timeoutSeconds: Int, probeURL: URL) async throws -> Bool {
        let start = Date()
        while Int(Date().timeIntervalSince(start)) < timeoutSeconds {
            try Task.checkCancellation()
            let elapsed = Int(Date().timeIntervalSince(start))
            let remaining = max(0, timeoutSeconds - elapsed)

            networkWarningMessage = String(
                format: String(localized: "Pobieranie zostało wstrzymane. Wznowienie nastąpi automatycznie po odzyskaniu połączenia (pozostało: %@ s)."),
                String(remaining)
            )
            downloadSpeedText = "0.0 MB/s"

            if await probeReachability(url: probeURL) {
                return true
            }

            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        networkWarningMessage = nil
        return false
    }

    func probeReachability(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...499).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
}
