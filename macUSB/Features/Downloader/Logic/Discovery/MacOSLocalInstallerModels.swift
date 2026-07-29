import Foundation

struct MacOSLocalInstallerIdentity: Hashable, Sendable {
    let version: String
    let build: String

    init?(version: String?, build: String?) {
        guard
            let normalizedVersion = Self.normalizedVersion(version),
            let normalizedBuild = Self.normalizedBuild(build)
        else {
            return nil
        }
        self.version = normalizedVersion
        self.build = normalizedBuild
    }

    func matches(_ entry: MacOSInstallerEntry) -> Bool {
        guard version == Self.normalizedVersion(entry.version) else {
            return false
        }
        let entryBuild = entry.build
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return entryBuild == "N/A" || build == entryBuild
    }

    private static func normalizedVersion(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty
        else {
            return nil
        }
        return normalized
    }

    private static func normalizedBuild(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              !normalized.isEmpty,
              normalized != "N/A"
        else {
            return nil
        }
        return normalized
    }
}

struct MacOSLocalInstallerCandidate: Sendable {
    let appURL: URL
    let diskImageURL: URL
}

struct MacOSLocalInstallerProcessResult: Sendable {
    let standardError: String
    let terminationStatus: Int32
}

struct MacOSLocalInstallerProcessFailure: LocalizedError, Sendable {
    let operation: String
    let result: MacOSLocalInstallerProcessResult

    var errorDescription: String? {
        "\(operation) zakonczyl sie kodem \(result.terminationStatus)"
            + (result.standardError.isEmpty ? "" : ": \(result.standardError)")
    }
}

struct MacOSLocalInstallerCleanupFailure: LocalizedError, Sendable {
    let failures: [String]

    var errorDescription: String? {
        "Nie udalo sie odmontowac obrazow lokalnego instalatora: "
            + failures.joined(separator: " | ")
    }
}

struct MacOSLocalInstallerCombinedFailure: LocalizedError {
    let operationError: Error
    let cleanupError: Error

    var errorDescription: String? {
        "\(operationError.localizedDescription); dodatkowo cleanup nie powiodl sie: \(cleanupError.localizedDescription)"
    }
}

func macOSLocalInstallerOffMain<T: Sendable>(
    _ operation: @escaping @Sendable () throws -> T
) async throws -> T {
    let task = Task.detached(priority: .utility, operation: operation)
    return try await withTaskCancellationHandler {
        try await task.value
    } onCancel: {
        task.cancel()
    }
}
