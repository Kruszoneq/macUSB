import Foundation
import Darwin

extension MontereyDownloadFlowModel {
    func runInstallerBuild(
        manifest: DownloadManifest,
        entry: MacOSInstallerEntry
    ) async throws {
        currentStage = .buildingInstaller
        buildStatusText = "Przygotowuję budowanie instalatora..."
        buildProgress = 0
        copyStatusText = "Oczekiwanie na gotowy instalator..."
        copyProgress = 0

        guard let packageURL = locateInstallAssistantPackage(in: manifest) else {
            throw DownloadFailureReason.assemblyFailed("Nie znaleziono pobranego InstallAssistant.pkg")
        }
        guard let outputDirectory = activeSessionOutputURL else {
            throw DownloadFailureReason.assemblyFailed("Brak katalogu output sesji")
        }

        let request = DownloaderAssemblyRequestPayload(
            packagePath: packageURL.path,
            outputDirectoryPath: outputDirectory.path,
            expectedAppName: "Install macOS Monterey.app",
            finalDestinationDirectoryPath: plannedInstallerFolderURL().path,
            cleanupSessionFiles: false,
            requesterUID: getuid()
        )
        cleanupDelegatedToHelper = request.cleanupSessionFiles

        let result = try await startAssemblyWithHelper(request: request)
        if result.cleanupRequested && result.cleanupSucceeded {
            sessionCleanupHandledByHelper = true
            helperCleanupFailureMessage = nil
            activeSessionRootURL = nil
            activeSessionPayloadURL = nil
            activeSessionOutputURL = nil
        } else if result.cleanupRequested {
            sessionCleanupHandledByHelper = false
            helperCleanupFailureMessage = result.cleanupErrorMessage
        } else {
            // Cleanup sesji wykonujemy zawsze jako osobny, ostatni etap
            // bezposrednio przed podsumowaniem.
            sessionCleanupHandledByHelper = false
            helperCleanupFailureMessage = nil
        }

        guard result.success else {
            throw DownloadFailureReason.assemblyFailed(result.errorMessage ?? "Helper zwrocil blad assembly")
        }
        guard let outputAppPath = result.outputAppPath else {
            throw DownloadFailureReason.assemblyFailed("Helper nie zwrocil sciezki do instalatora .app")
        }

        buildStatusText = "Instalator .app został zbudowany..."
        buildProgress = 1.0
        completedStages.insert(.buildingInstaller)

        currentStage = .copyingInstaller
        copyStatusText = "Przenoszę gotowy instalator do lokalizacji docelowej..."
        copyProgress = 0.55

        let finalAppURL = URL(fileURLWithPath: outputAppPath)
        guard FileManager.default.fileExists(atPath: finalAppURL.path) else {
            throw DownloadFailureReason.assemblyFailed("Zbudowana aplikacja instalatora nie istnieje")
        }

        finalInstallerAppURL = finalAppURL
        copyStatusText = "Weryfikuję gotowy instalator..."
        copyProgress = 0.85
        try validateFinalInstallerApp(
            at: finalAppURL,
            packageURL: packageURL,
            expectedVersion: entry.version,
            expectedBuild: entry.build
        )
        copyStatusText = "Instalator zapisano w \(finalAppURL.path)"
        copyProgress = 1.0
        completedStages.insert(.copyingInstaller)

        AppLogging.info(
            "Monterey installer move status=success destination=\(finalAppURL.path)",
            category: "Downloader"
        )
    }

    private func locateInstallAssistantPackage(in manifest: DownloadManifest) -> URL? {
        let preferred = manifest.items.first { item in
            item.name.localizedCaseInsensitiveContains("InstallAssistant.pkg")
                || item.url.lastPathComponent.localizedCaseInsensitiveContains("InstallAssistant.pkg")
        }

        guard let preferred else { return nil }
        return downloadedFileURLsByItemID[preferred.id]
    }

    private func startAssemblyWithHelper(
        request: DownloaderAssemblyRequestPayload
    ) async throws -> DownloaderAssemblyResultPayload {
        try await withCheckedThrowingContinuation { continuation in
            var didFinish = false
            let finish: (Result<DownloaderAssemblyResultPayload, Error>) -> Void = { result in
                guard !didFinish else { return }
                didFinish = true
                switch result {
                case let .success(payload):
                    continuation.resume(returning: payload)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            PrivilegedOperationClient.shared.startDownloaderAssembly(
                request: request,
                onEvent: { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.isCopyStageStatus(event.statusText) {
                            self.completedStages.insert(.buildingInstaller)
                            self.currentStage = .copyingInstaller
                            self.copyStatusText = event.statusText
                            let normalizedCopyProgress = min(
                                1.0,
                                max(0, (event.percent - 0.90) / 0.10)
                            )
                            self.copyProgress = max(self.copyProgress, normalizedCopyProgress)
                        } else {
                            self.currentStage = .buildingInstaller
                            let normalizedBuildProgress = min(
                                1.0,
                                max(0, event.percent / 0.90)
                            )
                            self.buildProgress = max(self.buildProgress ?? 0, normalizedBuildProgress)
                            self.buildStatusText = event.statusText
                        }
                        if let logLine = event.logLine, !logLine.isEmpty {
                            AppLogging.info(logLine, category: "Downloader")
                        }
                    }
                },
                onCompletion: { [weak self] result in
                    Task { @MainActor [weak self] in
                        self?.activeAssemblyWorkflowID = nil
                    }
                    finish(.success(result))
                },
                onStartError: { message in
                    finish(.failure(DownloadFailureReason.assemblyFailed(message)))
                },
                onStarted: { [weak self] workflowID in
                    Task { @MainActor [weak self] in
                        self?.activeAssemblyWorkflowID = workflowID
                    }
                }
            )
        }
    }

    private func isCopyStageStatus(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized.contains("przenoszenie instalatora")
            || normalized.contains("katalogu docelowego")
    }

    func plannedInstallerFolderURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Poza iCloud", isDirectory: true)
    }

    private func validateFinalInstallerApp(
        at appURL: URL,
        packageURL: URL,
        expectedVersion: String,
        expectedBuild: String
    ) throws {
        verifyCodeSignatureNonBlocking(of: appURL, packageURL: packageURL)
        try verifyInstallerBuildIfAvailable(
            of: appURL,
            expectedBuild: expectedBuild,
            expectedVersion: expectedVersion
        )
    }

    private func verifyCodeSignatureNonBlocking(of appURL: URL, packageURL: URL) {
        let expectedCodesign = "exit=0"
        let codesign = runAndCapture(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--verbose=2", appURL.path]
        )

        if codesign.status == 0 {
            AppLogging.info(
                "Weryfikacja podpisu .app (codesign): expected=\(expectedCodesign), actual=exit=\(codesign.status) dla \(appURL.lastPathComponent).",
                category: "Downloader"
            )
        } else {
            let details = codesign.output.isEmpty ? "brak szczegolow" : codesign.output
            AppLogging.error(
                "Weryfikacja podpisu .app (codesign) niezgodna: expected=\(expectedCodesign), actual=exit=\(codesign.status), details=\(details). Kontynuuje bez blokowania przeplywu.",
                category: "Downloader"
            )
            if isLegacyResourceEnvelopeWarning(details) {
                verifyPackageSignatureWithPkgutilNonBlocking(packageURL: packageURL)
            }
        }
    }

    private func isLegacyResourceEnvelopeWarning(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("resource envelope is obsolete")
            || normalized.contains("custom omit rules")
    }

    private func verifyPackageSignatureWithPkgutilNonBlocking(packageURL: URL) {
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            AppLogging.info(
                "Legacy warning z codesign: pomijam pkgutil, bo pakiet nie jest juz dostepny pod \(packageURL.path).",
                category: "Downloader"
            )
            return
        }

        let expectedPkgutil = "signature valid (exit=0)"
        let pkgutil = runAndCapture(
            executable: "/usr/sbin/pkgutil",
            arguments: ["--check-signature", packageURL.path]
        )

        if pkgutil.status == 0 {
            let details = pkgutil.output.isEmpty ? "brak szczegolow" : pkgutil.output
            AppLogging.info(
                "Fallback podpisu pakietu (pkgutil): expected=\(expectedPkgutil), actual=signature valid (exit=\(pkgutil.status)), details=\(details)",
                category: "Downloader"
            )
        } else {
            let details = pkgutil.output.isEmpty ? "brak szczegolow" : pkgutil.output
            AppLogging.error(
                "Fallback podpisu pakietu (pkgutil) niezgodny: expected=\(expectedPkgutil), actual=invalid/warning (exit=\(pkgutil.status)), details=\(details). Kontynuuje bez blokowania przeplywu.",
                category: "Downloader"
            )
        }
    }

    private func runAndCapture(executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (-1, error.localizedDescription)
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (task.terminationStatus, output)
    }

    private func verifyInstallerBuildIfAvailable(
        of appURL: URL,
        expectedBuild: String,
        expectedVersion: String
    ) throws {
        let expected = expectedBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty, expected.caseInsensitiveCompare("N/A") != .orderedSame else {
            AppLogging.info(
                "Brak oczekiwanego builda dla \(appURL.lastPathComponent) (wersja \(expectedVersion)); pomijam walidacje build.",
                category: "Downloader"
            )
            return
        }

        let discoveredBuilds = extractInstallerBuildCandidates(from: appURL)
        guard !discoveredBuilds.isEmpty else {
            AppLogging.info(
                "Nie udalo sie odczytac builda z \(appURL.lastPathComponent); pomijam walidacje build (oczekiwano \(expected)).",
                category: "Downloader"
            )
            return
        }

        if discoveredBuilds.contains(where: { $0.caseInsensitiveCompare(expected) == .orderedSame }) {
            return
        }

        if isKnownCompatibleBuildAlias(
            expectedBuild: expected,
            discoveredBuilds: discoveredBuilds,
            expectedVersion: expectedVersion
        ) {
            AppLogging.info(
                "Akceptuje kompatybilny alias builda dla \(appURL.lastPathComponent): expected=\(expected), actual=\(discoveredBuilds.joined(separator: ", ")), version=\(expectedVersion).",
                category: "Downloader"
            )
            return
        }

        let actual = discoveredBuilds.joined(separator: ", ")
        throw DownloadFailureReason.assemblyFailed(
            "Finalny instalator ma build \(actual), oczekiwano \(expected)"
        )
    }

    private func isKnownCompatibleBuildAlias(
        expectedBuild: String,
        discoveredBuilds: [String],
        expectedVersion: String
    ) -> Bool {
        let normalizedVersion = expectedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedVersion == "12.7.6" else { return false }

        let expectedCanonical = expectedBuild.uppercased()
        let discoveredCanonical = Set(discoveredBuilds.map { $0.uppercased() })
        let montereyAliasSet: Set<String> = ["21H1319", "21H1320"]

        guard montereyAliasSet.contains(expectedCanonical) else { return false }
        return !discoveredCanonical.intersection(montereyAliasSet).isEmpty
    }

    private func extractInstallerBuildCandidates(from appURL: URL) -> [String] {
        var values: [String] = []

        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return []
        }

        let infoKeys = ["ProductBuildVersion", "BuildVersion"]
        for key in infoKeys {
            if let value = plist[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    values.append(trimmed)
                }
            }
        }

        let installInfoURL = appURL
            .appendingPathComponent("Contents/SharedSupport", isDirectory: true)
            .appendingPathComponent("InstallInfo.plist")
        if let installInfoData = try? Data(contentsOf: installInfoURL),
           let installInfo = try? PropertyListSerialization.propertyList(from: installInfoData, options: [], format: nil) as? [String: Any] {
            if let rootBuild = installInfo["Build"] as? String {
                let trimmed = rootBuild.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    values.append(trimmed)
                }
            }
            if let systemImageInfo = installInfo["System Image Info"] as? [String: Any] {
                if let imageBuild = systemImageInfo["build"] as? String {
                    let trimmed = imageBuild.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        values.append(trimmed)
                    }
                }
            }
        }

        let osBuildRegex = try? NSRegularExpression(pattern: #"^[0-9]{1,3}[A-Za-z][0-9]{1,6}[A-Za-z]?$"#)
        let filtered = values.filter { candidate in
            let range = NSRange(location: 0, length: candidate.utf16.count)
            return osBuildRegex?.firstMatch(in: candidate, options: [], range: range) != nil
        }

        var unique: [String] = []
        var seen = Set<String>()
        for value in filtered {
            let canonical = value.lowercased()
            if seen.insert(canonical).inserted {
                unique.append(value)
            }
        }
        return unique
    }
}
