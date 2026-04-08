import Foundation

extension MacOSCatalogService {
    func enrichedWithInstallerSizes(_ entries: [MacOSInstallerEntry]) async throws -> (entries: [MacOSInstallerEntry], summary: SizeProbeSummary) {
        var enriched = entries
        let probeState = SizeProbeRunState()

        let totalEntries = entries.count
        let catalogPrefilledSizes = entries.reduce(into: 0) { partialResult, entry in
            if entry.installerSizeText != nil {
                partialResult += 1
            }
        }

        let pendingProbeEntries = entries.enumerated().compactMap { index, entry -> (Int, MacOSInstallerEntry)? in
            entry.installerSizeText == nil ? (index, entry) : nil
        }

        var resolvedByNetworkProbe = 0
        var unresolvedAfterProbe = 0
        var retriesPerformed = 0
        var skippedDueToTrustFailedHost = 0

        if !pendingProbeEntries.isEmpty {
            let maxConcurrency = max(1, Constants.maxSizeProbeConcurrency)
            var pendingIterator = pendingProbeEntries.makeIterator()

            try await withThrowingTaskGroup(of: SizeProbeResult.self) { group in
                for _ in 0..<min(maxConcurrency, pendingProbeEntries.count) {
                    guard let (index, entry) = pendingIterator.next() else { break }
                    group.addTask {
                        try await self.probeSize(for: entry, at: index, state: probeState)
                    }
                }

                while let result = try await group.next() {
                    retriesPerformed += result.retriesPerformed
                    skippedDueToTrustFailedHost += result.skippedDueToTrustFailedHost

                    if let sizeText = result.sizeText {
                        enriched[result.index] = enriched[result.index].with(installerSizeText: sizeText)
                        resolvedByNetworkProbe += 1
                    } else {
                        unresolvedAfterProbe += 1
                    }

                    if let (nextIndex, nextEntry) = pendingIterator.next() {
                        group.addTask {
                            try await self.probeSize(for: nextEntry, at: nextIndex, state: probeState)
                        }
                    }
                }
            }
        }

        let snapshot = await probeState.summarySnapshot()
        let summary = SizeProbeSummary(
            totalEntries: totalEntries,
            catalogPrefilledSizes: catalogPrefilledSizes,
            resolvedByNetworkProbe: resolvedByNetworkProbe,
            unresolvedAfterProbe: unresolvedAfterProbe,
            skippedDueToTrustFailedHost: skippedDueToTrustFailedHost,
            retriesPerformed: retriesPerformed,
            trustFailedHosts: snapshot.trustFailedHosts,
            suppressedRepeatedFailureLogs: snapshot.suppressedRepeatedFailureLogs
        )

        return (enriched, summary)
    }

    func probeSize(for entry: MacOSInstallerEntry, at index: Int, state: SizeProbeRunState) async throws -> SizeProbeResult {
        let outcome = try await fetchInstallerSizeTextIfAvailable(from: entry.sourceURL, state: state)
        return SizeProbeResult(
            index: index,
            sizeText: outcome.sizeText,
            retriesPerformed: outcome.retriesPerformed,
            skippedDueToTrustFailedHost: outcome.skippedDueToTrustFailedHost
        )
    }

    func fetchInstallerSizeTextIfAvailable(from url: URL, state: SizeProbeRunState) async throws -> SizeProbeFetchOutcome {
        try Task.checkCancellation()
        guard isAllowedHost(url) else {
            return SizeProbeFetchOutcome(sizeText: nil, retriesPerformed: 0, skippedDueToTrustFailedHost: 0)
        }

        var retriesPerformed = 0
        var skippedDueToTrustFailedHost = 0

        for probeURL in sizeProbeURLs(for: url) {
            try Task.checkCancellation()
            guard isAllowedHost(probeURL) else { continue }

            let host = probeURL.host?.lowercased() ?? ""
            if !host.isEmpty, await state.isTrustFailedHost(host) {
                skippedDueToTrustFailedHost += 1
                continue
            }

            let probeResult = try await fetchContentLengthWithRetry(from: probeURL, state: state)
            retriesPerformed += probeResult.retriesPerformed

            if let bytes = probeResult.bytes, bytes > 0 {
                return SizeProbeFetchOutcome(
                    sizeText: formatSizeInGigabytes(bytes: bytes),
                    retriesPerformed: retriesPerformed,
                    skippedDueToTrustFailedHost: skippedDueToTrustFailedHost
                )
            }
        }

        return SizeProbeFetchOutcome(
            sizeText: nil,
            retriesPerformed: retriesPerformed,
            skippedDueToTrustFailedHost: skippedDueToTrustFailedHost
        )
    }

    func sizeProbeURLs(for url: URL) -> [URL] {
        var result: [URL] = []
        var seen: Set<String> = []

        func append(_ candidate: URL?) {
            guard let candidate else { return }
            guard seen.insert(candidate.absoluteString).inserted else { return }
            result.append(candidate)
        }

        // Prefer HTTPS and newer updates host first for legacy support links.
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if components.scheme?.lowercased() == "http" {
                components.scheme = "https"
                append(components.url)
            }
        }
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let host = components.host?.lowercased() {
            components.scheme = "https"
            if host == "updates-http.cdn-apple.com" {
                components.host = "updates.cdn-apple.com"
                append(components.url)
            } else if host == "updates.cdn-apple.com" {
                components.host = "updates-http.cdn-apple.com"
                append(components.url)
            }
        }

        append(url)

        return result
    }

    func fetchContentLengthWithRetry(from url: URL, state: SizeProbeRunState) async throws -> (bytes: Int64?, retriesPerformed: Int) {
        var retriesPerformed = 0
        let attempts = max(1, Constants.maxSizeProbeAttempts)

        for attempt in 1...attempts {
            do {
                let bytes = try await fetchContentLength(from: url, state: state)
                return (bytes, retriesPerformed)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if isTrustFailure(error), let host = url.host?.lowercased(), !host.isEmpty {
                    await state.markTrustFailedHost(host)
                    return (nil, retriesPerformed)
                }

                let shouldRetry = isTransientProbeError(error) && attempt < attempts
                if shouldRetry {
                    retriesPerformed += 1
                    let delay = retryDelayNanoseconds(forAttempt: attempt)
                    AppLogging.info(
                        "SizeProbe stage=retry host=\(url.host ?? "unknown") attempt=\(attempt + 1) delay_ms=\(delay / 1_000_000)",
                        category: "Downloader"
                    )
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }

                return (nil, retriesPerformed)
            }
        }

        return (nil, retriesPerformed)
    }

    func fetchContentLength(from url: URL, state: SizeProbeRunState) async throws -> Int64? {
        do {
            if let headLength = try await fetchContentLengthWithHEAD(from: url) {
                return headLength
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await logProbeFailure(method: .head, url: url, error: error, action: "fallback_to_range", state: state)
        }

        do {
            return try await fetchContentLengthWithRangeProbe(from: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await logProbeFailure(method: .range, url: url, error: error, action: "skip_size", state: state)
            throw error
        }
    }

    func logProbeFailure(method: ProbeMethod, url: URL, error: Error, action: String, state: SizeProbeRunState) async {
        let nsError = error as NSError
        let host = url.host?.lowercased() ?? "unknown"
        let streamCode = streamErrorCode(from: nsError)
        let failureKey = "\(method.rawValue)|\(host)|\(nsError.domain)|\(nsError.code)|\(streamCode ?? 0)"

        guard await state.shouldLogFailure(for: failureKey) else { return }

        let trustFlag = isTrustFailure(error) ? "1" : "0"
        AppLogging.info(
            "SizeProbe stage=content_length method=\(method.rawValue) host=\(host) code=\(nsError.code) stream=\(streamCode ?? 0) trust=\(trustFlag) action=\(action) url=\(url.absoluteString)",
            category: "Downloader"
        )
    }

    func isTransientProbeError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch URLError.Code(rawValue: nsError.code) {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    func isTrustFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch URLError.Code(rawValue: nsError.code) {
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return true
        default:
            return streamErrorCode(from: nsError) == -9802
        }
    }

    func streamErrorCode(from error: NSError) -> Int? {
        if let value = error.userInfo["_kCFNetworkCFStreamSSLErrorOriginalValue"] as? NSNumber {
            return value.intValue
        }
        if let value = error.userInfo["_kCFStreamErrorCodeKey"] as? NSNumber {
            return value.intValue
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return streamErrorCode(from: underlying)
        }
        return nil
    }

    func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let base = Constants.sizeProbeRetryBaseDelayNanoseconds
        let multiplier = UInt64(1 << max(0, attempt - 1))
        let jitter = UInt64((attempt * 73) % 170) * 1_000_000
        return base * multiplier + jitter
    }

    func logSizeProbeSummary(_ summary: SizeProbeSummary) {
        AppLogging.info(
            "SizeProbe summary total=\(summary.totalEntries) prefilled=\(summary.catalogPrefilledSizes) network=\(summary.resolvedByNetworkProbe) unresolved=\(summary.unresolvedAfterProbe) skipped_failed_host=\(summary.skippedDueToTrustFailedHost) retries=\(summary.retriesPerformed) trust_failed_hosts=\(summary.trustFailedHosts) suppressed_logs=\(summary.suppressedRepeatedFailureLogs)",
            category: "Downloader"
        )
    }

    func fetchContentLengthWithHEAD(from url: URL) async throws -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = Constants.requestTimeout

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        guard (200...299).contains(httpResponse.statusCode) else { return nil }
        let resolvedURL = httpResponse.url ?? url
        guard isAllowedHost(resolvedURL), isDownloadAssetURL(resolvedURL) else { return nil }
        return contentLength(from: httpResponse)
    }

    func fetchContentLengthWithRangeProbe(from url: URL) async throws -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = Constants.requestTimeout
        request.setValue(Constants.byteRangeProbe, forHTTPHeaderField: "Range")

        let (_, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else { return nil }
        let resolvedURL = httpResponse.url ?? url
        guard isAllowedHost(resolvedURL), isDownloadAssetURL(resolvedURL) else { return nil }
        return contentLength(from: httpResponse)
    }

    func contentLength(from response: HTTPURLResponse) -> Int64? {
        if let contentRangeHeader = response.value(forHTTPHeaderField: "Content-Range"),
           let slashIndex = contentRangeHeader.lastIndex(of: "/") {
            let totalLength = contentRangeHeader[contentRangeHeader.index(after: slashIndex)...]
            if let parsed = Int64(totalLength), parsed > 0 {
                return parsed
            }
        }

        if let contentLengthHeader = response.value(forHTTPHeaderField: "Content-Length"),
           let contentLength = Int64(contentLengthHeader),
           contentLength > 0 {
            return contentLength
        }

        return nil
    }

    func formatSizeInGigabytes(bytes: Int64) -> String {
        let sizeInGigabytes = Double(bytes) / 1_000_000_000
        return String(format: "%.2fGB", locale: Locale(identifier: "en_US_POSIX"), sizeInGigabytes)
    }
}
