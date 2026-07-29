import Foundation

extension MacOSCatalogService {
    func discoverLocalInstallers(
        matching entries: [MacOSInstallerEntry],
        applicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) async throws -> MacOSInstallerDiscoveryResult {
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
                "Nie udalo sie odczytac folderu /Applications podczas wykrywania lokalnych instalatorow: \(error.localizedDescription)",
                category: "Downloader"
            )
            return MacOSInstallerDiscoveryResult(
                entries: entries,
                unrecognizedLocalInstallerCount: 0
            )
        }

        AppLogging.info(
            "Wykrywanie lokalnych instalatorow: znaleziono \(applicationURLs.count) kandydatow nazwowych w /Applications.",
            category: "Downloader"
        )

        var identities = Set<MacOSLocalInstallerIdentity>()
        var unrecognizedCount = 0

        for appURL in applicationURLs {
            try Task.checkCancellation()

            guard let candidate = try await macOSLocalInstallerOffMain({
                validatedLocalInstallerCandidate(at: appURL)
            }) else {
                AppLogging.info(
                    "Pominieto aplikacje podobna z nazwy do instalatora, ale bez wymaganej struktury lub payloadu: \(appURL.path)",
                    category: "Downloader"
                )
                continue
            }

            do {
                if let identity = try await readLocalInstallerIdentity(from: candidate) {
                    identities.insert(identity)
                    AppLogging.info(
                        "Rozpoznano lokalny instalator \(appURL.lastPathComponent): version=\(identity.version), build=\(identity.build).",
                        category: "Downloader"
                    )
                } else {
                    unrecognizedCount += 1
                    AppLogging.error(
                        "Nie udalo sie odczytac wersji lub buildu lokalnego instalatora: \(appURL.path)",
                        category: "Downloader"
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                unrecognizedCount += 1
                AppLogging.error(
                    "Blad odczytu tozsamosci lokalnego instalatora \(appURL.path): \(error.localizedDescription)",
                    category: "Downloader"
                )
            }
        }

        let enrichedEntries = entries.map { entry in
            entry.with(isDownloaded: identities.contains { $0.matches(entry) })
        }
        for identity in identities where !entries.contains(where: identity.matches) {
            AppLogging.info(
                "Lokalny instalator version=\(identity.version), build=\(identity.build) nie wystepuje w aktywnym katalogu Apple; pozostaje bez oznaczenia.",
                category: "Downloader"
            )
        }

        AppLogging.info(
            "Wykrywanie lokalnych instalatorow zakonczone: rozpoznane tozsamosci=\(identities.count), nierozpoznane=\(unrecognizedCount), dopasowane wpisy katalogu=\(enrichedEntries.filter(\.isDownloaded).count).",
            category: "Downloader"
        )
        return MacOSInstallerDiscoveryResult(
            entries: enrichedEntries,
            unrecognizedLocalInstallerCount: unrecognizedCount
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
                    "Cleanup po anulowaniu wykrywania lokalnego instalatora nie powiodl sie: \(error.localizedDescription)",
                    category: "Downloader"
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
