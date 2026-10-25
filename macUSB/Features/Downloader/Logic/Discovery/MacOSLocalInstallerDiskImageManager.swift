import Foundation

final class MacOSLocalInstallerDiskImageManager: @unchecked Sendable {
    private final class MountRecord {
        let mountURL: URL
        var attachCompleted = false

        init(mountURL: URL) {
            self.mountURL = mountURL
        }
    }

    let temporaryRoot: URL

    private let fileManager: FileManager
    private let processRunner: MacOSLocalInstallerProcessRunner
    private var mounts: [MountRecord] = []

    init(
        processRunner: MacOSLocalInstallerProcessRunner,
        fileManager: FileManager = .default
    ) throws {
        self.processRunner = processRunner
        self.fileManager = fileManager
        temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "macUSB-local-installer-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
    }

    func mount(imageURL: URL, label: String) async throws -> URL {
        try Task.checkCancellation()
        let mountURL = temporaryRoot.appendingPathComponent(
            "\(label)-mount-\(UUID().uuidString)",
            isDirectory: true
        )
        try await macOSLocalInstallerOffMain {
            try FileManager.default.createDirectory(
                at: mountURL,
                withIntermediateDirectories: true
            )
        }

        let record = MountRecord(mountURL: mountURL)
        mounts.append(record)

        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: [
                "attach",
                "-readonly",
                "-nobrowse",
                "-noverify",
                "-plist",
                "-mountpoint",
                mountURL.path,
                imageURL.path
            ]
        )
        guard result.terminationStatus == 0 else {
            throw MacOSLocalInstallerProcessFailure(
                operation: "hdiutil attach \(imageURL.lastPathComponent)",
                result: result
            )
        }
        record.attachCompleted = true
        try Task.checkCancellation()
        return mountURL
    }

    func cleanup() async throws {
        var failures: [String] = []

        for record in mounts.reversed() {
            if !record.attachCompleted && !isMounted(at: record.mountURL) {
                continue
            }

            do {
                try await detach(record.mountURL)
            } catch {
                failures.append("\(record.mountURL.path): \(error.localizedDescription)")
            }
        }

        guard failures.isEmpty else {
            AppLogging.error(
                "Local installer image cleanup failed; temporary directory remains at \(temporaryRoot.path). \(failures.joined(separator: " | "))",
                stage: .downloader, workflow: .discovery
            )
            throw MacOSLocalInstallerCleanupFailure(failures: failures)
        }

        if fileManager.fileExists(atPath: temporaryRoot.path) {
            do {
                try fileManager.removeItem(at: temporaryRoot)
            } catch {
                AppLogging.error(
                    "Could not remove temporary local installer discovery directory \(temporaryRoot.path): \(error.localizedDescription)",
                    stage: .downloader, workflow: .discovery
                )
                throw MacOSLocalInstallerCleanupFailure(
                    failures: [
                        "\(temporaryRoot.path): \(error.localizedDescription)"
                    ]
                )
            }
        }
        mounts.removeAll()
    }

    private func detach(_ mountURL: URL) async throws {
        var diagnostics: [String] = []

        for attempt in 1...2 {
            do {
                let result = try await processRunner.run(
                    executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                    arguments: ["detach", mountURL.path],
                    cancellationPolicy: .ignoreCancellation
                )
                if result.terminationStatus == 0 {
                    return
                }
                let diagnostic =
                    "proba \(attempt), kod \(result.terminationStatus): \(result.standardError)"
                diagnostics.append(diagnostic)
                AppLogging.error(
                    "Normal local installer detach failed (\(diagnostic)).",
                    stage: .downloader, workflow: .discovery
                )
            } catch {
                let diagnostic =
                    "proba \(attempt), blad uruchomienia: \(error.localizedDescription)"
                diagnostics.append(diagnostic)
                AppLogging.error(
                    "Could not start normal local installer detach (\(diagnostic)).",
                    stage: .downloader, workflow: .discovery
                )
            }
        }

        do {
            let forceResult = try await processRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", mountURL.path, "-force"],
                cancellationPolicy: .ignoreCancellation
            )
            if forceResult.terminationStatus == 0 {
                return
            }
            diagnostics.append(
                "force, kod \(forceResult.terminationStatus): \(forceResult.standardError)"
            )
        } catch {
            diagnostics.append(
                "force, blad uruchomienia: \(error.localizedDescription)"
            )
        }
        throw MacOSLocalInstallerCleanupFailure(failures: diagnostics)
    }

    private func isMounted(at mountURL: URL) -> Bool {
        let targetPath = mountURL.standardizedFileURL.path
        return fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: []
        )?.contains {
            $0.standardizedFileURL.path == targetPath
        } ?? false
    }
}
