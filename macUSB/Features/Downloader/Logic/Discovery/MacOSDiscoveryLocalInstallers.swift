import Foundation

extension MacOSCatalogService {
    func discoverLocalInstallers(
        applicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) async throws -> MacOSLocalInstallerDiscoverySnapshot {
        try Task.checkCancellation()

        let applicationURLs: [URL]
        do {
            applicationURLs = try await macOSLocalInstallerOffMain {
                try FileManager.default.contentsOfDirectory(
                    at: applicationsURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )
                .filter(isNamedMacOSInstallerApplication)
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                        == .orderedAscending
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLogging.error(
                "Could not read /Applications during local installer discovery: \(error.localizedDescription)",
                stage: .downloader, workflow: .discovery
            )
            return MacOSLocalInstallerDiscoverySnapshot(
                identities: [],
                unrecognizedInstallerCount: 0
            )
        }

        AppLogging.info(
            "Local installer discovery: found \(applicationURLs.count) name candidates in /Applications.",
            stage: .downloader, workflow: .discovery
        )

        var identities = Set<MacOSLocalInstallerIdentity>()
        var unrecognizedCount = 0

        for appURL in applicationURLs {
            try Task.checkCancellation()

            guard let candidate = try await macOSLocalInstallerOffMain({
                validatedLocalInstallerCandidate(at: appURL)
            }) else {
                AppLogging.info(
                    "Ignored installer-like app without required structure or payload: \(appURL.path)",
                    stage: .downloader, workflow: .discovery
                )
                continue
            }

            do {
                if let identity = try await readLocalInstallerIdentity(from: candidate) {
                    identities.insert(identity)
                    AppLogging.info(
                        "Recognized local installer \(appURL.lastPathComponent): version=\(identity.version), build=\(identity.build).",
                        stage: .downloader, workflow: .discovery
                    )
                } else {
                    unrecognizedCount += 1
                    AppLogging.error(
                        "Could not read local installer version or build: \(appURL.path)",
                        stage: .downloader, workflow: .discovery
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                unrecognizedCount += 1
                AppLogging.error(
                    "Failed to read local installer identity \(appURL.path): \(error.localizedDescription)",
                    stage: .downloader, workflow: .discovery
                )
            }
        }

        AppLogging.info(
            "Local installer discovery completed: recognized identities=\(identities.count), unrecognized=\(unrecognizedCount).",
            stage: .downloader, workflow: .discovery
        )
        return MacOSLocalInstallerDiscoverySnapshot(
            identities: identities,
            unrecognizedInstallerCount: unrecognizedCount
        )
    }

    func applyingLocalInstallerSnapshot(
        _ snapshot: MacOSLocalInstallerDiscoverySnapshot,
        to entries: [MacOSInstallerEntry]
    ) -> MacOSInstallerDiscoveryResult {
        let enrichedEntries = entries.map { entry in
            entry.with(
                isDownloaded: snapshot.identities.contains { $0.matches(entry) }
            )
        }
        for identity in snapshot.identities where !entries.contains(where: identity.matches) {
            AppLogging.info(
                "Local installer version=\(identity.version), build=\(identity.build) absent from active Apple catalog; leaving it unmarked.",
                stage: .downloader, workflow: .discovery
            )
        }

        AppLogging.info(
            "Applied local installer discovery result: recognized identities=\(snapshot.identities.count), unrecognized=\(snapshot.unrecognizedInstallerCount), matched catalog entries=\(enrichedEntries.filter(\.isDownloaded).count).",
            stage: .downloader, workflow: .discovery
        )
        return MacOSInstallerDiscoveryResult(
            entries: enrichedEntries,
            unrecognizedLocalInstallerCount: snapshot.unrecognizedInstallerCount
        )
    }

    private nonisolated func isNamedMacOSInstallerApplication(_ url: URL) -> Bool {
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return false
        }

        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return name.hasPrefix("install macos")
            || name.hasPrefix("install os x")
            || name.hasPrefix("install mac os x")
    }

    private nonisolated func validatedLocalInstallerCandidate(
        at appURL: URL
    ) -> MacOSLocalInstallerCandidate? {
        let fileManager = FileManager.default
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let createInstallMediaURL = appURL.appendingPathComponent(
            "Contents/Resources/createinstallmedia"
        )
        let sharedSupportDMGURL = appURL.appendingPathComponent(
            "Contents/SharedSupport/SharedSupport.dmg"
        )
        let installESDDMGURL = appURL.appendingPathComponent(
            "Contents/SharedSupport/InstallESD.dmg"
        )

        guard
            isRegularLocalInstallerFile(infoPlistURL, fileManager: fileManager),
            let infoPlistData = try? Data(contentsOf: infoPlistURL),
            (try? PropertyListSerialization.propertyList(
                from: infoPlistData,
                format: nil
            )) is [String: Any]
        else {
            return nil
        }

        if isRegularLocalInstallerFile(createInstallMediaURL, fileManager: fileManager),
           isRegularLocalInstallerFile(sharedSupportDMGURL, fileManager: fileManager) {
            return MacOSLocalInstallerCandidate(
                appURL: appURL,
                diskImageURL: sharedSupportDMGURL
            )
        }

        if isRegularLocalInstallerFile(installESDDMGURL, fileManager: fileManager) {
            return MacOSLocalInstallerCandidate(
                appURL: appURL,
                diskImageURL: installESDDMGURL
            )
        }

        return nil
    }

    private nonisolated func isRegularLocalInstallerFile(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func readLocalInstallerIdentity(
        from candidate: MacOSLocalInstallerCandidate
    ) async throws -> MacOSLocalInstallerIdentity? {
        let processRunner = MacOSLocalInstallerProcessRunner()
        let imageManager = try MacOSLocalInstallerDiskImageManager(
            processRunner: processRunner
        )
        let metadataReader = MacOSLocalInstallerMetadataReader(
            processRunner: processRunner
        )

        var identity: MacOSLocalInstallerIdentity?
        var operationError: Error?

        do {
            let mountURL = try await imageManager.mount(
                imageURL: candidate.diskImageURL,
                label: "installer"
            )
            identity = try await metadataReader.readIdentity(
                candidate: candidate,
                mountedImageURL: mountURL,
                imageManager: imageManager
            )
        } catch {
            operationError = error
        }

        do {
            try await imageManager.cleanup()
        } catch {
            if operationError is CancellationError {
                AppLogging.error(
                    "Cleanup after local installer discovery cancellation failed: \(error.localizedDescription)",
                    stage: .downloader, workflow: .discovery
                )
                throw CancellationError()
            }
            if let operationError {
                throw MacOSLocalInstallerCombinedFailure(
                    operationError: operationError,
                    cleanupError: error
                )
            }
            throw error
        }

        if let operationError {
            throw operationError
        }
        try Task.checkCancellation()
        return identity
    }
}
