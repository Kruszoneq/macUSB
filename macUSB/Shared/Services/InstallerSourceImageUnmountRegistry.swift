import Foundation

enum InstallerSourceImageFamily: String, CaseIterable {
    case windows
    case linux
}

final class InstallerSourceImageUnmountRegistry {
    static let shared = InstallerSourceImageUnmountRegistry()

    private let queue = DispatchQueue(label: "macUSB.SourceImageUnmountRegistry")
    private var trackedSourcePaths: [InstallerSourceImageFamily: Set<String>] = [:]
    private var trackedMountHints: [InstallerSourceImageFamily: Set<String>] = [:]

    private init() {
        InstallerSourceImageFamily.allCases.forEach { family in
            trackedSourcePaths[family] = []
            trackedMountHints[family] = []
        }
    }

    func registerSourceImage(
        path: String?,
        family: InstallerSourceImageFamily,
        mountHint: String? = nil,
        reason: String,
        stage: AppLogging.Stage = .analysis
    ) {
        let normalizedPath = normalizedFileSystemPath(path)
        let normalizedHint = normalizedMountIdentifier(mountHint)

        queue.sync {
            if let normalizedPath {
                trackedSourcePaths[family, default: []].insert(normalizedPath)
            }
            if let normalizedHint {
                trackedMountHints[family, default: []].insert(normalizedHint)
            }
        }

        if let normalizedPath {
            AppLogging.info(
                "Source image cleanup registry: tracked source \(family.rawValue): \(normalizedPath) [reason=\(reason)]",
                stage: stage, workflow: family == .windows ? .windows : .linux
            )
        }
        if let normalizedHint {
            AppLogging.info(
                "Source image cleanup registry: tracked mount hint \(family.rawValue): \(normalizedHint) [reason=\(reason)]",
                stage: stage, workflow: family == .windows ? .windows : .linux
            )
        }
    }

    @discardableResult
    func detachAllTrackedImagesOnAppTermination() -> Bool {
        detachTrackedImages(
            reason: "app_termination",
            families: Set(InstallerSourceImageFamily.allCases),
            clearAfter: true
        )
    }

    @discardableResult
    func detachTrackedImages(
        reason: String,
        families: Set<InstallerSourceImageFamily>,
        clearAfter: Bool
    ) -> Bool {
        let cleanupToken = AppActiveOperationRegistry.shared.begin(
            kind: .cleanup,
            context: "source_image_detach:\(reason)"
        )
        defer { cleanupToken.finish() }
        let snapshot = queue.sync { () -> (paths: [InstallerSourceImageFamily: Set<String>], hints: [InstallerSourceImageFamily: Set<String>]) in
            let paths = trackedSourcePaths.filter { families.contains($0.key) }
            let hints = trackedMountHints.filter { families.contains($0.key) }
            return (paths, hints)
        }

        let trackedPaths = snapshot.paths.values.reduce(into: Set<String>()) { result, value in
            result.formUnion(value)
        }
        let fallbackHints = snapshot.hints.values.reduce(into: Set<String>()) { result, value in
            result.formUnion(value)
        }

        guard !trackedPaths.isEmpty || !fallbackHints.isEmpty else {
            AppLogging.info(
                "Source image cleanup registry: no tracked images to clean up [reason=\(reason)]",
                stage: .analysis
            )
            if clearAfter {
                clearTrackedState(for: families)
            }
            return true
        }

        let collected = collectDetachTargetsForTrackedPaths(trackedPaths)
        var succeeded = collected.succeeded
        var detachTargets = collected.targets
        if detachTargets.isEmpty && !fallbackHints.isEmpty {
            detachTargets = Array(fallbackHints)
        }

        detachTargets = orderedDetachTargets(detachTargets)
        if detachTargets.isEmpty {
            AppLogging.info(
                "Source image cleanup registry: no active entities to detach [reason=\(reason)]",
                stage: .analysis
            )
            if clearAfter {
                clearTrackedState(for: families)
            }
            return succeeded
        }

        AppLogging.info(
            "Source image cleanup registry: detaching (\(detachTargets.count) entities) [reason=\(reason)]",
            stage: .analysis
        )

        for target in detachTargets {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["detach", target, "-force"]
            let errorPipe = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                succeeded = false
                AppLogging.error(
                    "Source image cleanup registry: failed to start detach for \(target): \(error.localizedDescription)",
                    stage: .analysis
                )
                continue
            }

            if process.terminationStatus == 0 {
                AppLogging.info(
                    "Source image cleanup registry: detached \(target)",
                    stage: .analysis
                )
            } else {
                succeeded = false
                let stderrText = String(
                    decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                if stderrText.isEmpty {
                    AppLogging.error(
                        "Source image cleanup registry: detach failed for \(target) (exit code \(process.terminationStatus))",
                        stage: .analysis
                    )
                } else {
                    AppLogging.error(
                        "Source image cleanup registry: detach failed for \(target): \(stderrText)",
                        stage: .analysis
                    )
                }
            }
        }

        if clearAfter {
            clearTrackedState(for: families)
        }
        return succeeded
    }

    private func clearTrackedState(for families: Set<InstallerSourceImageFamily>) {
        queue.sync {
            for family in families {
                trackedSourcePaths[family] = []
                trackedMountHints[family] = []
            }
        }
    }

    private func normalizedFileSystemPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func normalizedMountIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/dev/") {
            return URL(fileURLWithPath: trimmed).path
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).resolvingSymlinksInPath().standardizedFileURL.path
        }
        return trimmed
    }

    private func collectDetachTargetsForTrackedPaths(_ trackedPaths: Set<String>) -> (targets: [String], succeeded: Bool) {
        guard !trackedPaths.isEmpty else { return ([], true) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            AppLogging.error(
                "Source image cleanup registry: failed to start hdiutil info: \(error.localizedDescription)",
                stage: .analysis
            )
            return ([], false)
        }
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let stderrText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                AppLogging.error(
                    "Source image cleanup registry: hdiutil info exited with code \(process.terminationStatus)",
                    stage: .analysis
                )
            } else {
                AppLogging.error(
                    "Source image cleanup registry: hdiutil info failed: \(stderrText)",
                    stage: .analysis
                )
            }
            return ([], false)
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: outputData,
            options: [],
            format: nil
        ) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            AppLogging.error(
                "Source image cleanup registry: hdiutil info returned invalid image data.",
                stage: .analysis
            )
            return ([], false)
        }

        var targets = Set<String>()
        for image in images {
            guard let imagePath = image["image-path"] as? String else { continue }
            let normalizedImagePath = URL(fileURLWithPath: imagePath)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
            guard trackedPaths.contains(normalizedImagePath) else { continue }

            guard let entities = image["system-entities"] as? [[String: Any]] else { continue }
            for entity in entities {
                if let devEntry = normalizedMountIdentifier(entity["dev-entry"] as? String) {
                    targets.insert(devEntry)
                }
                if let mountPoint = normalizedMountIdentifier(entity["mount-point"] as? String) {
                    targets.insert(mountPoint)
                }
            }
        }

        return (Array(targets), true)
    }

    private func orderedDetachTargets(_ targets: [String]) -> [String] {
        let uniqueTargets = Array(Set(targets))
        return uniqueTargets.sorted { lhs, rhs in
            let lhsIsDevice = lhs.hasPrefix("/dev/")
            let rhsIsDevice = rhs.hasPrefix("/dev/")
            if lhsIsDevice != rhsIsDevice {
                return lhsIsDevice && !rhsIsDevice
            }
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs > rhs
        }
    }
}
