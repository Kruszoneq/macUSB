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
        reason: String
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
                "Rejestr mount cleanup: zapisano źródło \(family.rawValue): \(normalizedPath) [reason=\(reason)]",
                category: "ImageCleanup"
            )
        }
        if let normalizedHint {
            AppLogging.info(
                "Rejestr mount cleanup: zapisano hint mount \(family.rawValue): \(normalizedHint) [reason=\(reason)]",
                category: "ImageCleanup"
            )
        }
    }

    func detachAllTrackedImagesOnAppTermination() {
        detachTrackedImages(
            reason: "app_termination",
            families: Set(InstallerSourceImageFamily.allCases),
            clearAfter: true
        )
    }

    func detachTrackedImages(
        reason: String,
        families: Set<InstallerSourceImageFamily>,
        clearAfter: Bool
    ) {
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
                "Rejestr mount cleanup: brak śledzonych obrazów dla cleanupu [reason=\(reason)]",
                category: "ImageCleanup"
            )
            if clearAfter {
                clearTrackedState(for: families)
            }
            return
        }

        var detachTargets = collectDetachTargetsForTrackedPaths(trackedPaths)
        if detachTargets.isEmpty && !fallbackHints.isEmpty {
            detachTargets = Array(fallbackHints)
        }

        detachTargets = orderedDetachTargets(detachTargets)
        if detachTargets.isEmpty {
            AppLogging.info(
                "Rejestr mount cleanup: nie znaleziono aktywnych encji do odmontowania [reason=\(reason)]",
                category: "ImageCleanup"
            )
            if clearAfter {
                clearTrackedState(for: families)
            }
            return
        }

        AppLogging.info(
            "Rejestr mount cleanup: start odmontowania (\(detachTargets.count) encji) [reason=\(reason)]",
            category: "ImageCleanup"
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
                AppLogging.error(
                    "Rejestr mount cleanup: nie udało się uruchomić detach dla \(target): \(error.localizedDescription)",
                    category: "ImageCleanup"
                )
                continue
            }

            if process.terminationStatus == 0 {
                AppLogging.info(
                    "Rejestr mount cleanup: odmontowano \(target)",
                    category: "ImageCleanup"
                )
            } else {
                let stderrText = String(
                    decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                if stderrText.isEmpty {
                    AppLogging.error(
                        "Rejestr mount cleanup: detach nie powiódł się dla \(target) (kod \(process.terminationStatus))",
                        category: "ImageCleanup"
                    )
                } else {
                    AppLogging.error(
                        "Rejestr mount cleanup: detach nie powiódł się dla \(target): \(stderrText)",
                        category: "ImageCleanup"
                    )
                }
            }
        }

        if clearAfter {
            clearTrackedState(for: families)
        }
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

    private func collectDetachTargetsForTrackedPaths(_ trackedPaths: Set<String>) -> [String] {
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
                "Rejestr mount cleanup: nie udało się uruchomić hdiutil info: \(error.localizedDescription)",
                category: "ImageCleanup"
            )
            return []
        }
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let stderrText = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                AppLogging.error(
                    "Rejestr mount cleanup: hdiutil info zwrócił kod \(process.terminationStatus)",
                    category: "ImageCleanup"
                )
            } else {
                AppLogging.error(
                    "Rejestr mount cleanup: hdiutil info błąd: \(stderrText)",
                    category: "ImageCleanup"
                )
            }
            return []
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: outputData,
            options: [],
            format: nil
        ) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return []
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

        return Array(targets)
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
