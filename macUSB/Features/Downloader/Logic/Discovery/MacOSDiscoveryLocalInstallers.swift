import Foundation

extension MacOSCatalogService {
    private nonisolated struct LocalInstallerIdentity: Hashable, Sendable {
        let version: String
        let build: String

        init?(version: String?, build: String?) {
            guard
                let normalizedVersion = Self.normalizeVersion(version),
                let normalizedBuild = Self.normalizeBuild(build)
            else {
                return nil
            }
            self.version = normalizedVersion
            self.build = normalizedBuild
        }

        private static func normalizeVersion(_ value: String?) -> String? {
            guard let normalized = value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                  !normalized.isEmpty
            else {
                return nil
            }
            return normalized
        }

        private static func normalizeBuild(_ value: String?) -> String? {
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

    private nonisolated struct LocalInstallerCandidate: Sendable {
        let appURL: URL
        let diskImageURL: URL
    }

    private nonisolated struct LocalInstallerProcessResult: Sendable {
        let standardOutput: Data
        let standardError: String
        let terminationStatus: Int32
    }

    private nonisolated final class LegacyDistributionParserDelegate:
        NSObject,
        XMLParserDelegate,
        @unchecked Sendable
    {
        private static let supportedKeys: Set<String> = [
            "macOSProductVersion",
            "macOSProductBuildVersion",
            "ProductVersion",
            "ProductBuildVersion",
            "OSVersion",
            "Build"
        ]

        private(set) var values: [String: String] = [:]
        private var currentElement: String?
        private var currentText = ""
        private var pendingKey: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if pendingKey != nil && elementName != "string" {
                pendingKey = nil
            }
            currentElement = elementName
            currentText = ""

            if elementName == "options",
               let build = attributeDict["osBuildVersion"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !build.isEmpty {
                values["osBuildVersion"] = build
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard currentElement == "key" || currentElement == "string" else {
                return
            }
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

            if elementName == "key" {
                pendingKey = Self.supportedKeys.contains(value) ? value : nil
            } else if elementName == "string", let pendingKey {
                if !value.isEmpty {
                    values[pendingKey] = value
                }
                self.pendingKey = nil
            }

            currentElement = nil
            currentText = ""
        }
    }

    private nonisolated final class CancellableProcess: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func register(_ process: Process) {
            lock.lock()
            self.process = process
            let shouldTerminate = cancelled
            lock.unlock()

            if shouldTerminate, process.isRunning {
                process.terminate()
            }
        }

        func clear() {
            lock.lock()
            process = nil
            lock.unlock()
        }

        func terminate() {
            lock.lock()
            cancelled = true
            let runningProcess = process
            lock.unlock()

            if runningProcess?.isRunning == true {
                runningProcess?.terminate()
            }
        }

        var isCancelled: Bool {
            lock.lock()
            let value = cancelled
            lock.unlock()
            return value
        }
    }

    func discoverLocalInstallers(
        matching entries: [MacOSInstallerEntry],
        applicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) async throws -> MacOSInstallerDiscoveryResult {
        try Task.checkCancellation()

        let candidates: [URL]
        do {
            candidates = try await performOffMain {
                try FileManager.default.contentsOfDirectory(
                    at: applicationsURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )
                .filter(isNamedMacOSInstallerApplication)
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
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
            "Wykrywanie lokalnych instalatorow: znaleziono \(candidates.count) kandydatow nazwowych w /Applications.",
            category: "Downloader"
        )

        var identities = Set<LocalInstallerIdentity>()
        var unrecognizedCount = 0

        for appURL in candidates {
            try Task.checkCancellation()

            guard let candidate = try await performOffMain({
                validatedCandidate(at: appURL)
            }) else {
                AppLogging.info(
                    "Pominieto aplikacje podobna z nazwy do instalatora, ale bez wymaganej struktury lub payloadu: \(appURL.path)",
                    category: "Downloader"
                )
                continue
            }

            do {
                if let identity = try await readIdentity(from: candidate) {
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
            entry.with(isDownloaded: identities.contains { identity in
                localIdentity(identity, matches: entry)
            })
        }
        for identity in identities where !entries.contains(where: {
            localIdentity(identity, matches: $0)
        }) {
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

    private nonisolated func validatedCandidate(at appURL: URL) -> LocalInstallerCandidate? {
        let fileManager = FileManager.default
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        let createInstallMediaURL = appURL.appendingPathComponent(
            "Contents/Resources/createinstallmedia",
            isDirectory: false
        )
        let sharedSupportDMGURL = appURL.appendingPathComponent(
            "Contents/SharedSupport/SharedSupport.dmg",
            isDirectory: false
        )
        let installESDDMGURL = appURL.appendingPathComponent(
            "Contents/SharedSupport/InstallESD.dmg",
            isDirectory: false
        )

        guard
            isRegularFile(infoPlistURL, fileManager: fileManager),
            let infoPlistData = try? Data(contentsOf: infoPlistURL),
            (try? PropertyListSerialization.propertyList(
                from: infoPlistData,
                format: nil
            )) is [String: Any]
        else {
            return nil
        }

        if isRegularFile(createInstallMediaURL, fileManager: fileManager),
           isRegularFile(sharedSupportDMGURL, fileManager: fileManager) {
            return LocalInstallerCandidate(appURL: appURL, diskImageURL: sharedSupportDMGURL)
        }

        if isRegularFile(installESDDMGURL, fileManager: fileManager) {
            return LocalInstallerCandidate(appURL: appURL, diskImageURL: installESDDMGURL)
        }

        return nil
    }

    private nonisolated func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func readIdentity(from candidate: LocalInstallerCandidate) async throws -> LocalInstallerIdentity? {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("macUSB-local-installer-\(UUID().uuidString)", isDirectory: true)
        let mountURL = temporaryRoot.appendingPathComponent("mount", isDirectory: true)

        try fileManager.createDirectory(at: mountURL, withIntermediateDirectories: true)
        var shouldAttemptDetach = false

        do {
            shouldAttemptDetach = true
            let attachResult = try await runLocalInstallerProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: [
                    "attach",
                    "-readonly",
                    "-nobrowse",
                    "-noverify",
                    "-plist",
                    "-mountpoint",
                    mountURL.path,
                    candidate.diskImageURL.path
                ]
            )
            guard attachResult.terminationStatus == 0 else {
                throw localInstallerProcessError(
                    operation: "hdiutil attach",
                    result: attachResult
                )
            }
            try Task.checkCancellation()

            var identity = try await performOffMain {
                try Task.checkCancellation()
                return identityFromMountedImage(at: mountURL)
            }
            if identity == nil {
                identity = try await identityFromLegacyInstallerPackage(
                    candidate: candidate,
                    mountedImageURL: mountURL,
                    temporaryRoot: temporaryRoot
                )
            }
            if identity == nil {
                identity = try await identityFromNestedBaseSystem(
                    mountedImageURL: mountURL,
                    temporaryRoot: temporaryRoot
                )
            }
            await detachLocalInstallerImageIfNeeded(
                mountURL: mountURL,
                shouldAttemptDetach: shouldAttemptDetach
            )
            removeTemporaryRoot(temporaryRoot, fileManager: fileManager)
            try Task.checkCancellation()
            return identity
        } catch {
            await detachLocalInstallerImageIfNeeded(
                mountURL: mountURL,
                shouldAttemptDetach: shouldAttemptDetach
            )
            removeTemporaryRoot(temporaryRoot, fileManager: fileManager)
            throw error
        }
    }

    private nonisolated func identityFromMountedImage(at mountURL: URL) -> LocalInstallerIdentity? {
        let fileManager = FileManager.default
        let mobileAssetNames = [
            "com_apple_MobileAsset_MacSoftwareUpdate.xml",
            "com_apple_MobileAsset_MacSoftwareUpdate.plist"
        ]

        for fileName in mobileAssetNames {
            if let metadataURL = firstFile(named: fileName, under: mountURL, fileManager: fileManager),
               let propertyList = propertyList(at: metadataURL),
               let identity = firstIdentity(in: propertyList) {
                return identity
            }
        }

        let systemVersionCandidates = [
            mountURL.appendingPathComponent(
                "System/Library/CoreServices/SystemVersion.plist",
                isDirectory: false
            ),
            mountURL.appendingPathComponent(
                "BaseSystem/System/Library/CoreServices/SystemVersion.plist",
                isDirectory: false
            )
        ]
        for systemVersionURL in systemVersionCandidates {
            guard let dictionary = propertyList(at: systemVersionURL) as? [String: Any] else {
                continue
            }
            if let identity = LocalInstallerIdentity(
                version: dictionary["ProductVersion"] as? String,
                build: dictionary["ProductBuildVersion"] as? String
            ) {
                return identity
            }
        }

        if let systemVersionURL = firstFile(
            named: "SystemVersion.plist",
            under: mountURL,
            fileManager: fileManager
        ),
           let dictionary = propertyList(at: systemVersionURL) as? [String: Any] {
            return LocalInstallerIdentity(
                version: dictionary["ProductVersion"] as? String,
                build: dictionary["ProductBuildVersion"] as? String
            )
        }

        return nil
    }

    private func identityFromLegacyInstallerPackage(
        candidate: LocalInstallerCandidate,
        mountedImageURL: URL,
        temporaryRoot: URL
    ) async throws -> LocalInstallerIdentity? {
        let packageURL = try await performOffMain {
            try Task.checkCancellation()
            return firstFile(
                named: "OSInstall.mpkg",
                under: mountedImageURL,
                fileManager: FileManager.default
            )
        }
        guard let packageURL else {
            return nil
        }

        let extractionURL = temporaryRoot.appendingPathComponent(
            "legacy-distribution-\(UUID().uuidString)",
            isDirectory: true
        )
        try await performOffMain {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: extractionURL,
                withIntermediateDirectories: true
            )
        }

        let extractionResult = try await runLocalInstallerProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/xar"),
            arguments: [
                "-xf",
                packageURL.path,
                "-C",
                extractionURL.path,
                "Distribution"
            ]
        )
        guard extractionResult.terminationStatus == 0 else {
            throw localInstallerProcessError(
                operation: "xar Distribution",
                result: extractionResult
            )
        }

        let distributionURL = extractionURL.appendingPathComponent(
            "Distribution",
            isDirectory: false
        )
        return try await performOffMain {
            try Task.checkCancellation()
            return legacyDistributionIdentity(
                distributionURL: distributionURL,
                appURL: candidate.appURL
            )
        }
    }

    private nonisolated func legacyDistributionIdentity(
        distributionURL: URL,
        appURL: URL
    ) -> LocalInstallerIdentity? {
        guard let distributionData = try? Data(contentsOf: distributionURL) else {
            return nil
        }

        let delegate = LegacyDistributionParserDelegate()
        let parser = XMLParser(data: distributionData)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }

        let version = firstNonEmptyValue(
            for: [
                "macOSProductVersion",
                "ProductVersion",
                "OSVersion"
            ],
            in: delegate.values
        ) ?? installerVersionFromInstallInfo(appURL: appURL)
        let build = firstNonEmptyValue(
            for: [
                "macOSProductBuildVersion",
                "ProductBuildVersion",
                "osBuildVersion",
                "Build"
            ],
            in: delegate.values
        )
        return LocalInstallerIdentity(version: version, build: build)
    }

    private func identityFromNestedBaseSystem(
        mountedImageURL: URL,
        temporaryRoot: URL
    ) async throws -> LocalInstallerIdentity? {
        let baseSystemImageURL = try await performOffMain {
            try Task.checkCancellation()
            return firstFile(
                named: "BaseSystem.dmg",
                under: mountedImageURL,
                fileManager: FileManager.default,
                includeHiddenFiles: true
            )
        }
        guard let baseSystemImageURL else {
            return nil
        }

        let nestedMountURL = temporaryRoot.appendingPathComponent(
            "base-system-mount",
            isDirectory: true
        )
        try await performOffMain {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: nestedMountURL,
                withIntermediateDirectories: true
            )
        }

        var shouldAttemptDetach = false
        do {
            shouldAttemptDetach = true
            let attachResult = try await runLocalInstallerProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: [
                    "attach",
                    "-readonly",
                    "-nobrowse",
                    "-noverify",
                    "-plist",
                    "-mountpoint",
                    nestedMountURL.path,
                    baseSystemImageURL.path
                ]
            )
            guard attachResult.terminationStatus == 0 else {
                throw localInstallerProcessError(
                    operation: "hdiutil attach BaseSystem.dmg",
                    result: attachResult
                )
            }
            try Task.checkCancellation()

            let identity = try await performOffMain {
                try Task.checkCancellation()
                return identityFromMountedImage(at: nestedMountURL)
            }
            await detachLocalInstallerImageIfNeeded(
                mountURL: nestedMountURL,
                shouldAttemptDetach: shouldAttemptDetach
            )
            try Task.checkCancellation()
            return identity
        } catch {
            await detachLocalInstallerImageIfNeeded(
                mountURL: nestedMountURL,
                shouldAttemptDetach: shouldAttemptDetach
            )
            throw error
        }
    }

    private nonisolated func installerVersionFromInstallInfo(appURL: URL) -> String? {
        let installInfoURL = appURL.appendingPathComponent(
            "Contents/SharedSupport/InstallInfo.plist",
            isDirectory: false
        )
        guard
            let dictionary = propertyList(at: installInfoURL) as? [String: Any]
        else {
            return nil
        }

        for key in ["Payload Image Info", "System Image Info"] {
            guard
                let imageInfo = dictionary[key] as? [String: Any],
                let version = imageInfo["version"] as? String,
                !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            return version
        }
        return nil
    }

    private nonisolated func firstNonEmptyValue(
        for keys: [String],
        in values: [String: String]
    ) -> String? {
        for key in keys {
            guard
                let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else {
                continue
            }
            return value
        }
        return nil
    }

    private nonisolated func propertyList(at url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    private nonisolated func firstIdentity(in propertyList: Any) -> LocalInstallerIdentity? {
        if let dictionary = propertyList as? [String: Any] {
            if let identity = LocalInstallerIdentity(
                version: dictionary["OSVersion"] as? String,
                build: dictionary["Build"] as? String
            ) {
                return identity
            }
            if let identity = LocalInstallerIdentity(
                version: dictionary["ProductVersion"] as? String,
                build: dictionary["ProductBuildVersion"] as? String
            ) {
                return identity
            }
            for value in dictionary.values {
                if let identity = firstIdentity(in: value) {
                    return identity
                }
            }
        } else if let array = propertyList as? [Any] {
            for value in array {
                if let identity = firstIdentity(in: value) {
                    return identity
                }
            }
        }
        return nil
    }

    private nonisolated func firstFile(
        named fileName: String,
        under directoryURL: URL,
        fileManager: FileManager,
        includeHiddenFiles: Bool = false
    ) -> URL? {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options,
            errorHandler: { url, error in
                Task { @MainActor in
                    AppLogging.error(
                        "Blad skanowania zamontowanego obrazu \(url.path): \(error.localizedDescription)",
                        category: "Downloader"
                    )
                }
                return true
            }
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            if Task.isCancelled {
                return nil
            }
            if fileURL.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame {
                return fileURL
            }
        }
        return nil
    }

    private nonisolated func localIdentity(
        _ identity: LocalInstallerIdentity,
        matches entry: MacOSInstallerEntry
    ) -> Bool {
        let entryVersion = entry.version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard identity.version == entryVersion else {
            return false
        }

        let entryBuild = entry.build
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return entryBuild == "N/A" || identity.build == entryBuild
    }

    private func detachLocalInstallerImageIfNeeded(
        mountURL: URL,
        shouldAttemptDetach: Bool
    ) async {
        guard shouldAttemptDetach else {
            return
        }

        do {
            let result = try await runLocalInstallerCleanupProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", mountURL.path]
            )
            if result.terminationStatus == 0 {
                return
            }
            AppLogging.error(
                "Standardowe odmontowanie lokalnego instalatora nie powiodlo sie: \(result.standardError)",
                category: "Downloader"
            )
        } catch {
            AppLogging.error(
                "Nie udalo sie uruchomic standardowego odmontowania lokalnego instalatora: \(error.localizedDescription)",
                category: "Downloader"
            )
        }

        do {
            let forceResult = try await runLocalInstallerCleanupProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", mountURL.path, "-force"]
            )
            if forceResult.terminationStatus != 0 {
                AppLogging.error(
                    "Wymuszone odmontowanie lokalnego instalatora nie powiodlo sie: \(forceResult.standardError)",
                    category: "Downloader"
                )
            }
        } catch {
            AppLogging.error(
                "Nie udalo sie uruchomic wymuszonego odmontowania lokalnego instalatora: \(error.localizedDescription)",
                category: "Downloader"
            )
        }
    }

    private nonisolated func removeTemporaryRoot(
        _ temporaryRoot: URL,
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: temporaryRoot.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: temporaryRoot)
        } catch {
            Task { @MainActor in
                AppLogging.error(
                    "Nie udalo sie usunac tymczasowego katalogu wykrywania lokalnego instalatora \(temporaryRoot.path): \(error.localizedDescription)",
                    category: "Downloader"
                )
            }
        }
    }

    private func runLocalInstallerProcess(
        executableURL: URL,
        arguments: [String]
    ) async throws -> LocalInstallerProcessResult {
        let cancellationBox = CancellableProcess()

        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<LocalInstallerProcessResult, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    if cancellationBox.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    let process = Process()
                    let standardOutput = Pipe()
                    let standardError = Pipe()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardOutput = standardOutput
                    process.standardError = standardError
                    cancellationBox.register(process)

                    do {
                        try process.run()
                        process.waitUntilExit()
                        let result = LocalInstallerProcessResult(
                            standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                            standardError: String(
                                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8
                            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                            terminationStatus: process.terminationStatus
                        )
                        cancellationBox.clear()
                        if cancellationBox.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: result)
                        }
                    } catch {
                        cancellationBox.clear()
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellationBox.terminate()
        }
        try Task.checkCancellation()
        return result
    }

    private func runLocalInstallerCleanupProcess(
        executableURL: URL,
        arguments: [String]
    ) async throws -> LocalInstallerProcessResult {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<LocalInstallerProcessResult, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let standardOutput = Pipe()
                let standardError = Pipe()
                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = standardOutput
                process.standardError = standardError

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(
                        returning: LocalInstallerProcessResult(
                            standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                            standardError: String(
                                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8
                            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                            terminationStatus: process.terminationStatus
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated func performOffMain<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let task = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated func localInstallerProcessError(
        operation: String,
        result: LocalInstallerProcessResult
    ) -> NSError {
        NSError(
            domain: "macUSB.Downloader.LocalInstallerDiscovery",
            code: Int(result.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "\(operation) zakonczyl sie kodem \(result.terminationStatus)"
                    + (result.standardError.isEmpty ? "" : ": \(result.standardError)")
            ]
        )
    }
}
