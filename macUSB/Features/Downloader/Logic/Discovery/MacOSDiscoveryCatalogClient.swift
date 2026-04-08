import Foundation

extension MacOSCatalogService {
    func fetchData(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard isAllowedHost(url) else {
            throw DiscoveryError.blockedHost(url)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = Constants.requestTimeout

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw DiscoveryError.invalidResponse(url)
        }

        return data
    }

    func isAllowedHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if Constants.allowedHosts.contains(host) {
            return true
        }
        if host == "apple.com" || host.hasSuffix(".apple.com") {
            return true
        }
        if host == "cdn-apple.com" || host.hasSuffix(".cdn-apple.com") {
            return true
        }
        return false
    }
}
