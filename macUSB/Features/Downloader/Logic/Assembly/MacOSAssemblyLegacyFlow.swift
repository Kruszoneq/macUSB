import Foundation

extension MontereyDownloadFlowModel {
    private struct LegacyAssemblyFiles {
        let installAssistantAuto: URL
        let recoveryHDMetaDmg: URL
        let installESDDmg: URL
    }

    func runLegacyAssemblyWithoutRoot(
        manifest: DownloadManifest,
        entry: MacOSInstallerEntry
    ) async throws -> URL {
        guard let sessionRootURL = activeSessionRootURL else {
            throw DownloadFailureReason.assemblyFailed("Brak katalogu sesji dla legacy assembly")
        }

        let files = try resolveLegacyAssemblyFiles(from: manifest)
        let workspaceURL = sessionRootURL.appendingPathComponent("legacy_assembly", isDirectory: true)
        let expandedURL = workspaceURL.appendingPathComponent("InstallAssistant", isDirectory: true)
        let mountURL = workspaceURL.appendingPathComponent("RecoveryHDMount_\(UUID().uuidString)", isDirectory: true)

        AppLogging.info(
            "Legacy assembly: start entry=\(entry.name) \(entry.version), workspace=\(workspaceURL.path)",
            category: "Downloader"
        )
        AppLogging.info(
            "Legacy assembly: inputs resolved InstallAssistantAuto=\(files.installAssistantAuto.lastPathComponent), RecoveryHDMetaDmg=\(files.recoveryHDMetaDmg.lastPathComponent), InstallESDDmg=\(files.installESDDmg.lastPathComponent)",
            category: "Downloader"
        )

        do {
            if FileManager.default.fileExists(atPath: workspaceURL.path) {
                try FileManager.default.removeItem(at: workspaceURL)
            }
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        } catch {
            throw DownloadFailureReason.assemblyFailed("Nie udalo sie przygotowac katalogu roboczego legacy: \(error.localizedDescription)")
        }

        var recoveryMounted = false
        defer {
            if recoveryMounted {
                AppLogging.info(
                    "Legacy assembly: cleanup detach recovery mount=\(mountURL.path)",
                    category: "Downloader"
                )
                _ = detachDiskImageWithRetry(
                    mountURL: mountURL,
                    context: "Legacy assembly cleanup"
                )
            }
            try? FileManager.default.removeItem(at: mountURL)
        }

        _ = try await runCommandWithBuildProgress(
            executable: "/usr/sbin/pkgutil",
            arguments: ["--expand-full", files.installAssistantAuto.path, expandedURL.path],
            statusText: String(localized: "Przygotowywanie plików instalatora..."),
            progressStart: 0.08,
            progressEnd: 0.26,
            stepName: "pkgutil expand"
        )

        let payloadURL = expandedURL.appendingPathComponent("Payload", isDirectory: true)
        let appURL = try locateInstallerApp(in: payloadURL)
        AppLogging.info(
            "Legacy assembly: detected app bundle path=\(appURL.path)",
            category: "Downloader"
        )
        let sharedSupportURL = appURL.appendingPathComponent("Contents/SharedSupport", isDirectory: true)

        try await runLegacyFileStepWithProgress(
            statusText: String(localized: "Przygotowywanie zasobów instalatora..."),
            progressStart: 0.28,
            progressEnd: 0.38,
            stepName: "prepare SharedSupport"
        ) {
            try FileManager.default.createDirectory(at: sharedSupportURL, withIntermediateDirectories: true)
            let installESDDestinationURL = sharedSupportURL.appendingPathComponent("InstallESD.dmg")
            try self.copyItemReplacing(sourceURL: files.installESDDmg, destinationURL: installESDDestinationURL)
        }

        _ = try await runCommandWithBuildProgress(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", "-readonly", "-nobrowse", files.recoveryHDMetaDmg.path, "-mountpoint", mountURL.path],
            statusText: String(localized: "Otwieranie pakietu odzyskiwania..."),
            progressStart: 0.40,
            progressEnd: 0.52,
            stepName: "attach recovery image"
        )
        recoveryMounted = true

        try await runLegacyFileStepWithProgress(
            statusText: String(localized: "Dodawanie wymaganych zasobów..."),
            progressStart: 0.54,
            progressEnd: 0.72,
            stepName: "copy RecoveryHD assets"
        ) {
            let mountedItems = try FileManager.default.contentsOfDirectory(
                at: mountURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for sourceItem in mountedItems {
                let destinationItem = sharedSupportURL.appendingPathComponent(sourceItem.lastPathComponent, isDirectory: false)
                try self.copyItemReplacing(sourceURL: sourceItem, destinationURL: destinationItem)
            }
        }

        buildStatusText = String(localized: "Kończenie przygotowania zasobów...")
        buildProgress = 0.74
        AppLogging.info(
            "Legacy assembly: detach recovery mount=\(mountURL.path)",
            category: "Downloader"
        )
        _ = detachDiskImageWithRetry(
            mountURL: mountURL,
            context: "Legacy assembly finalize"
        )
        recoveryMounted = false

        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let preferredName = expectedInstallerAppName(for: entry)
        let destinationURL = uniqueCollisionSafeURL(
            in: applicationsURL,
            preferredFileName: preferredName
        )
        if destinationURL.lastPathComponent != preferredName {
            AppLogging.info(
                "Legacy assembly: wykryto kolizje nazwy w /Applications, używam \(destinationURL.lastPathComponent)",
                category: "Downloader"
            )
        }
        try await runLegacyFileStepWithProgress(
            statusText: String(localized: "Kończenie przygotowania instalatora..."),
            progressStart: 0.80,
            progressEnd: 0.96,
            stepName: "copy installer to /Applications"
        ) {
            try self.copyItemReplacing(sourceURL: appURL, destinationURL: destinationURL)
        }

        AppLogging.info(
            "Legacy assembly: installer ready path=\(destinationURL.path)",
            category: "Downloader"
        )
        return destinationURL
    }

    func runOldestDiskImageAssemblyWithoutRoot(
        diskImageURL: URL,
        entry: MacOSInstallerEntry
    ) async throws -> URL {
        guard let sessionRootURL = activeSessionRootURL else {
            throw DownloadFailureReason.assemblyFailed("Brak katalogu sesji dla assembly najstarszego systemu")
        }

        let workspaceURL = sessionRootURL.appendingPathComponent("oldest_assembly", isDirectory: true)
        let mountURL = workspaceURL.appendingPathComponent("MountedDMG_\(UUID().uuidString)", isDirectory: true)
        let copiedPackageURL = workspaceURL.appendingPathComponent("InstallPackage.pkg")

        do {
            if FileManager.default.fileExists(atPath: workspaceURL.path) {
                try FileManager.default.removeItem(at: workspaceURL)
            }
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        } catch {
            throw DownloadFailureReason.assemblyFailed("Nie udalo sie przygotowac katalogu roboczego dla .dmg: \(error.localizedDescription)")
        }

        var mounted = false
        defer {
            if mounted {
                _ = detachDiskImageWithRetry(
                    mountURL: mountURL,
                    context: "Oldest assembly cleanup"
                )
            }
            try? FileManager.default.removeItem(at: mountURL)
        }

        _ = try await runCommandWithBuildProgress(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", "-readonly", "-nobrowse", diskImageURL.path, "-mountpoint", mountURL.path],
            statusText: String(localized: "Otwieranie obrazu instalatora..."),
            progressStart: 0.08,
            progressEnd: 0.24,
            stepName: "attach oldest dmg"
        )
        mounted = true

        let installerPackageURL = try locateInstallerPackage(in: mountURL)
        try await runLegacyFileStepWithProgress(
            statusText: String(localized: "Kopiowanie pakietu instalatora..."),
            progressStart: 0.26,
            progressEnd: 0.34,
            stepName: "copy oldest package"
        ) {
            try self.copyItemReplacing(sourceURL: installerPackageURL, destinationURL: copiedPackageURL)
        }

        let extractedAppURL = try await extractInstallerAppFromPackageWithoutInstaller(
            packageURL: copiedPackageURL,
            workspaceURL: workspaceURL,
            entry: entry
        )

        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let preferredName = expectedInstallerAppName(for: entry)
        let destinationURL = uniqueCollisionSafeURL(
            in: applicationsURL,
            preferredFileName: preferredName
        )

        try await runLegacyFileStepWithProgress(
            statusText: String(localized: "Kończenie przygotowania instalatora..."),
            progressStart: 0.86,
            progressEnd: 0.96,
            stepName: "copy oldest installer to /Applications"
        ) {
            try self.copyItemReplacing(sourceURL: extractedAppURL, destinationURL: destinationURL)
        }

        if destinationURL.lastPathComponent != preferredName {
            AppLogging.info(
                "Oldest assembly: wykryto kolizje nazwy w /Applications, używam \(destinationURL.lastPathComponent)",
                category: "Downloader"
            )
        }
        AppLogging.info(
            "Oldest assembly: installer ready path=\(destinationURL.path)",
            category: "Downloader"
        )

        return destinationURL
    }

    private func locateInstallerApp(in payloadURL: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: payloadURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DownloadFailureReason.assemblyFailed("Nie udalo sie przeszukac katalogu payload instalatora")
        }

        var firstApp: URL?
        for case let candidate as URL in enumerator {
            guard candidate.pathExtension.lowercased() == "app" else {
                continue
            }
            if candidate.lastPathComponent.lowercased().hasPrefix("install ") {
                return candidate
            }
            if firstApp == nil {
                firstApp = candidate
            }
        }

        if let firstApp {
            return firstApp
        }
        throw DownloadFailureReason.assemblyFailed("Nie znaleziono aplikacji instalatora .app po rozpakowaniu pakietu")
    }

    private func locateInstallerPackage(in mountedDiskImageURL: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: mountedDiskImageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw DownloadFailureReason.assemblyFailed("Nie udalo sie przeszukac zamontowanego obrazu .dmg")
        }

        var candidates: [URL] = []
        for case let candidate as URL in enumerator {
            guard candidate.pathExtension.lowercased() == "pkg" else {
                continue
            }
            candidates.append(candidate)
        }

        guard !candidates.isEmpty else {
            throw DownloadFailureReason.assemblyFailed("W zamontowanym obrazie .dmg nie znaleziono pakietu .pkg")
        }

        if let preferred = candidates.first(where: { $0.lastPathComponent.lowercased().contains("install") }) {
            return preferred
        }
        return candidates.sorted { lhs, rhs in
            lhs.path.count < rhs.path.count
        }.first!
    }

    private func extractInstallerAppFromPackageWithoutInstaller(
        packageURL: URL,
        workspaceURL: URL,
        entry: MacOSInstallerEntry
    ) async throws -> URL {
        let expandedURL = workspaceURL.appendingPathComponent("ExpandedPackage", isDirectory: true)
        let extractionRootURL = workspaceURL.appendingPathComponent("ExtractedPayload", isDirectory: true)

        try await runLegacyFileStepWithProgress(
            statusText: String(localized: "Przygotowywanie zawartości instalatora..."),
            progressStart: 0.36,
            progressEnd: 0.42,
            stepName: "prepare oldest extraction workspace"
        ) {
            if FileManager.default.fileExists(atPath: expandedURL.path) {
                try FileManager.default.removeItem(at: expandedURL)
            }
            if FileManager.default.fileExists(atPath: extractionRootURL.path) {
                try FileManager.default.removeItem(at: extractionRootURL)
            }
            try FileManager.default.createDirectory(at: extractionRootURL, withIntermediateDirectories: true)
        }

        _ = try await runCommandWithBuildProgress(
            executable: "/usr/sbin/pkgutil",
            arguments: ["--expand", packageURL.path, expandedURL.path],
            statusText: String(localized: "Rozpakowywanie pakietu instalatora..."),
            progressStart: 0.42,
            progressEnd: 0.54,
            stepName: "pkgutil expand oldest package"
        )

        let payloadURLs = locatePayloadFiles(in: expandedURL)
        guard !payloadURLs.isEmpty else {
            throw DownloadFailureReason.assemblyFailed("Nie znaleziono pliku Payload w rozpakowanej strukturze .pkg")
        }

        let containsPBZXPayload = payloadURLs.contains { url in
            detectPayloadCompression(for: url) == .pbzx
        }

        if containsPBZXPayload {
            let expandedFullURL = workspaceURL.appendingPathComponent("ExpandedFullPackage", isDirectory: true)
            _ = try await runCommandWithBuildProgress(
                executable: "/usr/sbin/pkgutil",
                arguments: ["--expand-full", packageURL.path, expandedFullURL.path],
                statusText: String(localized: "Przygotowywanie rozszerzonego rozpakowania..."),
                progressStart: 0.54,
                progressEnd: 0.78,
                stepName: "pkgutil expand-full oldest package"
            )
            let payloadDirectory = expandedFullURL.appendingPathComponent("Payload", isDirectory: true)
            let appURL = try locateInstallerApp(in: payloadDirectory)
            try await attachInstallESDIfNeeded(
                in: expandedFullURL,
                installerAppURL: appURL,
                entry: entry
            )
            return appURL
        }

        let totalPayloads = max(payloadURLs.count, 1)
        for (index, payloadURL) in payloadURLs.enumerated() {
            try Task.checkCancellation()
            let start = 0.54 + (Double(index) / Double(totalPayloads)) * 0.22
            let end = 0.54 + (Double(index + 1) / Double(totalPayloads)) * 0.22
            try await runLegacyFileStepWithProgress(
                statusText: String(
                    format: String(localized: "Przygotowywanie plików instalatora (%@/%@)..."),
                    String(index + 1),
                    String(payloadURLs.count)
                ),
                progressStart: start,
                progressEnd: end,
                stepName: "extract payload \(index + 1)"
            ) {
                try self.extractPayload(
                    payloadURL: payloadURL,
                    destinationDirectoryURL: extractionRootURL
                )
            }
        }

        let appURL = try locateInstallerApp(in: extractionRootURL)
        try await attachInstallESDIfNeeded(
            in: expandedURL,
            installerAppURL: appURL,
            entry: entry
        )
        return appURL
    }

    private func attachInstallESDIfNeeded(
        in expandedPackageRootURL: URL,
        installerAppURL: URL,
        entry: MacOSInstallerEntry
    ) async throws {
        guard let installESDSourceURL = locateInstallESD(in: expandedPackageRootURL) else {
            AppLogging.error(
                "Oldest assembly: brak InstallESD.dmg w rozpakowanym pakiecie \(expandedPackageRootURL.path) dla \(entry.version)",
                category: "Downloader"
            )
            throw DownloadFailureReason.assemblyFailed(
                String(localized: "Nie można dokończyć przygotowania. Brakuje pliku InstallESD.dmg. Spróbuj ponownie pobrać ten system.")
            )
        }
        AppLogging.info(
            "Oldest assembly: znaleziono InstallESD.dmg source=\(installESDSourceURL.path)",
            category: "Downloader"
        )

        try await runLegacyFileStepWithProgress(
            statusText: String(localized: "Dodawanie obrazu systemu do instalatora..."),
            progressStart: 0.78,
            progressEnd: 0.84,
            stepName: "copy InstallESD into SharedSupport"
        ) {
            let sharedSupportURL = installerAppURL.appendingPathComponent("Contents/SharedSupport", isDirectory: true)
            try FileManager.default.createDirectory(at: sharedSupportURL, withIntermediateDirectories: true)
            let installESDDestinationURL = sharedSupportURL.appendingPathComponent("InstallESD.dmg", isDirectory: false)
            try self.copyItemReplacing(sourceURL: installESDSourceURL, destinationURL: installESDDestinationURL)
        }
    }

    private func locateInstallESD(in expandedPackageRootURL: URL) -> URL? {
        let rootCandidate = expandedPackageRootURL.appendingPathComponent("InstallESD.dmg", isDirectory: false)
        if FileManager.default.fileExists(atPath: rootCandidate.path) {
            return rootCandidate
        }

        let nestedCandidate = expandedPackageRootURL
            .appendingPathComponent("InstallMacOSX.pkg", isDirectory: true)
            .appendingPathComponent("InstallESD.dmg", isDirectory: false)
        if FileManager.default.fileExists(atPath: nestedCandidate.path) {
            return nestedCandidate
        }

        guard let enumerator = FileManager.default.enumerator(
            at: expandedPackageRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var candidates: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.caseInsensitiveCompare("InstallESD.dmg") == .orderedSame else {
                continue
            }
            candidates.append(fileURL)
        }

        return candidates.sorted { lhs, rhs in
            lhs.path.count < rhs.path.count
        }.first
    }

    private func locatePayloadFiles(in directoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var payloads: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "Payload" else { continue }
            payloads.append(fileURL)
        }
        return payloads.sorted { lhs, rhs in
            lhs.path.count < rhs.path.count
        }
    }

    private enum PayloadCompression {
        case cpio
        case gzip
        case pbzx
        case unknown
    }

    private func detectPayloadCompression(for payloadURL: URL) -> PayloadCompression {
        guard let handle = try? FileHandle(forReadingFrom: payloadURL) else {
            return .unknown
        }
        defer { try? handle.close() }

        let headerData = (try? handle.read(upToCount: 8)) ?? Data()
        if headerData.count >= 4 {
            let text = String(data: headerData.prefix(4), encoding: .ascii)?.lowercased()
            if text == "pbzx" {
                return .pbzx
            }
        }
        if headerData.count >= 2 {
            let bytes = Array(headerData.prefix(2))
            if bytes == [0x1f, 0x8b] {
                return .gzip
            }
        }

        return .cpio
    }

    private func extractPayload(
        payloadURL: URL,
        destinationDirectoryURL: URL
    ) throws {
        let compression = detectPayloadCompression(for: payloadURL)
        let payloadPath = quotedShellPath(payloadURL.path)
        let extractCommand: String

        switch compression {
        case .gzip:
            extractCommand = "gzip -dc \(payloadPath) | cpio -idmu"
        case .pbzx:
            throw DownloadFailureReason.assemblyFailed(
                "Payload pbzx wymaga fallbacku przez pkgutil --expand-full"
            )
        case .cpio, .unknown:
            extractCommand = "cpio -idmu < \(payloadPath)"
        }

        try runShellCommand(
            command: extractCommand,
            currentDirectoryURL: destinationDirectoryURL
        )
    }

    private func runShellCommand(
        command: String,
        currentDirectoryURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = currentDirectoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw DownloadFailureReason.assemblyFailed(
                "Nie udalo sie uruchomic polecenia ekstrakcji payload: \(error.localizedDescription)"
            )
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errors = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let details = [output, errors]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty {
            AppLogging.info(
                "Oldest payload extraction output: \(details)",
                category: "Downloader"
            )
        }

        guard process.terminationStatus == 0 else {
            throw DownloadFailureReason.assemblyFailed(
                "Polecenie ekstrakcji payload zakonczone bledem (\(process.terminationStatus))."
            )
        }
    }

    private func quotedShellPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func copyItemReplacing(sourceURL: URL, destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func resolveLegacyAssemblyFiles(from manifest: DownloadManifest) throws -> LegacyAssemblyFiles {
        let requiredPackageIDs: [String: String] = [
            "com.apple.pkg.InstallAssistantAuto": "InstallAssistantAuto.pkg",
            "com.apple.pkg.RecoveryHDMetaDmg": "RecoveryHDMetaDmg.pkg",
            "com.apple.pkg.InstallESDDmg": "InstallESDDmg.pkg"
        ]

        var resolvedByID: [String: URL] = [:]
        for item in manifest.items {
            guard let packageID = item.packageIdentifier?.lowercased(),
                  requiredPackageIDs.keys.contains(where: { $0.lowercased() == packageID })
            else {
                continue
            }
            if let localURL = downloadedFileURLsByItemID[item.id] {
                resolvedByID[packageID] = localURL
            }
        }

        func resolveRequiredFile(_ packageIdentifier: String) -> URL? {
            if let byID = resolvedByID[packageIdentifier.lowercased()],
               FileManager.default.fileExists(atPath: byID.path) {
                return byID
            }
            guard let fallbackName = requiredPackageIDs[packageIdentifier] else { return nil }
            if let fallbackItem = manifest.items.first(where: { item in
                item.name.caseInsensitiveCompare(fallbackName) == .orderedSame
                    || item.url.lastPathComponent.caseInsensitiveCompare(fallbackName) == .orderedSame
            }), let fallbackURL = downloadedFileURLsByItemID[fallbackItem.id],
               FileManager.default.fileExists(atPath: fallbackURL.path) {
                return fallbackURL
            }
            return nil
        }

        guard let installAssistantAuto = resolveRequiredFile("com.apple.pkg.InstallAssistantAuto") else {
            throw DownloadFailureReason.assemblyFailed("Brak wymaganego pliku InstallAssistantAuto.pkg dla legacy assembly")
        }
        guard let recoveryHDMetaDmg = resolveRequiredFile("com.apple.pkg.RecoveryHDMetaDmg") else {
            throw DownloadFailureReason.assemblyFailed("Brak wymaganego pliku RecoveryHDMetaDmg.pkg dla legacy assembly")
        }
        guard let installESDDmg = resolveRequiredFile("com.apple.pkg.InstallESDDmg") else {
            throw DownloadFailureReason.assemblyFailed("Brak wymaganego pliku InstallESDDmg.pkg dla legacy assembly")
        }

        return LegacyAssemblyFiles(
            installAssistantAuto: installAssistantAuto,
            recoveryHDMetaDmg: recoveryHDMetaDmg,
            installESDDmg: installESDDmg
        )
    }
}
