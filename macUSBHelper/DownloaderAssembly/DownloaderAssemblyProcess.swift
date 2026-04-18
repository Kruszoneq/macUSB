import Foundation
import Darwin

extension DownloaderAssemblyExecutor {
    func runInstallerBasedOldestDiskImageAssemblyAndLocateApp(
        diskImageURL: URL,
        sessionRootDirectory: URL
    ) throws -> URL {
        let sourceMountURL = sessionRootDirectory.appendingPathComponent("sierra_source_mount", isDirectory: true)
        let stagingImageURL = sessionRootDirectory.appendingPathComponent("sierra_staging_workspace.dmg")
        let stagingMountURL = sessionRootDirectory.appendingPathComponent("sierra_staging_mount", isDirectory: true)

        if FileManager.default.fileExists(atPath: sourceMountURL.path) {
            _ = detachDiskImageWithRetry(
                mountURL: sourceMountURL,
                statusText: "Czyszczenie poprzedniego montowania obrazu..."
            )
            try? FileManager.default.removeItem(at: sourceMountURL)
        }
        if FileManager.default.fileExists(atPath: stagingMountURL.path) {
            _ = detachDiskImageWithRetry(
                mountURL: stagingMountURL,
                statusText: "Czyszczenie poprzedniego montowania obrazu..."
            )
            try? FileManager.default.removeItem(at: stagingMountURL)
        }
        if FileManager.default.fileExists(atPath: stagingImageURL.path) {
            try? FileManager.default.removeItem(at: stagingImageURL)
        }

        try FileManager.default.createDirectory(at: sourceMountURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingMountURL, withIntermediateDirectories: true)

        var sourceMounted = false
        var stagingMounted = false
        defer {
            if stagingMounted {
                _ = detachDiskImageWithRetry(
                    mountURL: stagingMountURL,
                    statusText: "Zamykanie obrazu roboczego Sierra..."
                )
            }
            if sourceMounted {
                _ = detachDiskImageWithRetry(
                    mountURL: sourceMountURL,
                    statusText: "Zamykanie obrazu źródłowego Sierra..."
                )
            }
            try? FileManager.default.removeItem(at: stagingMountURL)
            try? FileManager.default.removeItem(at: sourceMountURL)
            try? FileManager.default.removeItem(at: stagingImageURL)
        }

        emit(
            percent: 0.12,
            status: "Otwieranie obrazu instalatora...",
            logLine: "sierra-assembly source-mount start image=\(diskImageURL.path) mount=\(sourceMountURL.path)"
        )
        try runCommand(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                "-readonly",
                "-nobrowse",
                diskImageURL.path,
                "-mountpoint", sourceMountURL.path
            ]
        )
        sourceMounted = true
        emit(
            percent: nil,
            status: "Otwieranie obrazu instalatora...",
            logLine: "sierra-assembly source-mount success mount=\(sourceMountURL.path)"
        )

        let installerPackageURL = try locateInstallerPackage(in: sourceMountURL)
        emit(
            percent: 0.18,
            status: "Kopiowanie pakietu instalatora...",
            logLine: "sierra-assembly package-resolved path=\(installerPackageURL.path)"
        )

        let imageSizeGB = calculateLegacyImageSizeGB(from: sourceMountURL)
        emit(
            percent: 0.22,
            status: "Przygotowywanie zawartości instalatora...",
            logLine: "sierra-assembly staging-image create size=\(imageSizeGB)g path=\(stagingImageURL.path)"
        )
        try runCommand(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "create",
                "-fs", "HFS+",
                "-layout", "SPUD",
                "-size", "\(imageSizeGB)g",
                "-volname", "macUSBSierraInstaller",
                "-ov",
                stagingImageURL.path
            ]
        )

        emit(
            percent: 0.28,
            status: "Rozpakowywanie pakietu instalatora...",
            logLine: "sierra-assembly staging-mount start image=\(stagingImageURL.path) mount=\(stagingMountURL.path)"
        )
        try runCommand(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                stagingImageURL.path,
                "-noverify",
                "-nobrowse",
                "-mountpoint", stagingMountURL.path
            ]
        )
        stagingMounted = true
        emit(
            percent: nil,
            status: "Rozpakowywanie pakietu instalatora...",
            logLine: "sierra-assembly staging-mount success mount=\(stagingMountURL.path)"
        )

        let installerEnvironment = ProcessInfo.processInfo.environment.merging(["CM_BUILD": "CM_BUILD"]) { current, _ in current }
        emit(
            percent: 0.34,
            status: "Dodawanie obrazu systemu do instalatora...",
            logLine: "sierra-assembly installer start pkg=\(installerPackageURL.path) target=\(stagingMountURL.path) env=CM_BUILD"
        )
        try runInstallerProcess(
            installerInputURL: installerPackageURL,
            targetPath: stagingMountURL.path,
            statusText: "Dodawanie obrazu systemu do instalatora...",
            environment: installerEnvironment
        )
        emit(
            percent: nil,
            status: "Dodawanie obrazu systemu do instalatora...",
            logLine: "sierra-assembly installer finished target=\(stagingMountURL.path)"
        )

        guard let builtInstallerURL = locateInstallerApp(onMountedVolume: stagingMountURL) else {
            throw NSError(
                domain: "macUSBHelper",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Nie znaleziono aplikacji instalatora na obrazie roboczym."]
            )
        }
        emit(
            percent: 0.86,
            status: "Kończenie przygotowania instalatora...",
            logLine: "sierra-assembly app-resolved path=\(builtInstallerURL.path)"
        )

        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let destinationURL = uniqueCollisionSafeURL(
            in: applicationsURL,
            preferredFileName: request.expectedAppName
        )
        emit(
            percent: 0.90,
            status: "Kończenie przygotowania instalatora...",
            logLine: "sierra-assembly app-copy start source=\(builtInstallerURL.path) destination=\(destinationURL.path)"
        )
        try runCommand(
            executable: "/usr/bin/ditto",
            arguments: [builtInstallerURL.path, destinationURL.path]
        )
        emit(
            percent: 0.94,
            status: "Instalator gotowy",
            logLine: "sierra-assembly app-copy success destination=\(destinationURL.path)"
        )
        return destinationURL
    }

    @discardableResult
    private func detachDiskImageWithRetry(
        mountURL: URL,
        statusText: String
    ) -> Bool {
        let normalArguments = ["detach", mountURL.path]
        for attempt in 1...2 {
            do {
                try runCommand(
                    executable: "/usr/bin/hdiutil",
                    arguments: normalArguments
                )
                emit(
                    percent: nil,
                    status: statusText,
                    logLine: "legacy-assembly detach success attempt=\(attempt) mode=normal mount=\(mountURL.path)"
                )
                return true
            } catch {
                emit(
                    percent: nil,
                    status: statusText,
                    logLine: "legacy-assembly detach failed attempt=\(attempt) mode=normal mount=\(mountURL.path) error=\(error.localizedDescription)"
                )
                if attempt == 1 {
                    Thread.sleep(forTimeInterval: 0.25)
                }
            }
        }

        do {
            try runCommand(
                executable: "/usr/bin/hdiutil",
                arguments: ["detach", mountURL.path, "-force"]
            )
            emit(
                percent: nil,
                status: statusText,
                logLine: "legacy-assembly detach success mode=force mount=\(mountURL.path)"
            )
            return true
        } catch {
            emit(
                percent: nil,
                status: statusText,
                logLine: "legacy-assembly detach failed mode=force mount=\(mountURL.path) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    func cleanupSessionDirectory(_ sessionRootDirectory: URL) throws {
        guard FileManager.default.fileExists(atPath: sessionRootDirectory.path) else { return }
        try FileManager.default.removeItem(at: sessionRootDirectory)

        if FileManager.default.fileExists(atPath: sessionRootDirectory.path) {
            throw NSError(
                domain: "macUSBHelper",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Katalog sesji nadal istnieje po cleanup: \(sessionRootDirectory.path)"]
            )
        }
    }

    func runLegacyDistributionAndLocateApp(
        distributionURL: URL,
        sessionRootDirectory: URL,
        patchLegacyDistribution: Bool
    ) throws -> URL {
        let effectiveDistributionURL: URL
        if patchLegacyDistribution {
            effectiveDistributionURL = try createPatchedLegacyDistribution(
                from: distributionURL,
                sessionRootDirectory: sessionRootDirectory
            )
        } else {
            effectiveDistributionURL = distributionURL
        }

        let imageURL = sessionRootDirectory.appendingPathComponent("legacy_installer_workspace.dmg")
        let mountURL = sessionRootDirectory.appendingPathComponent("legacy_installer_mount", isDirectory: true)

        if FileManager.default.fileExists(atPath: mountURL.path) {
            _ = detachDiskImageWithRetry(
                mountURL: mountURL,
                statusText: "Czyszczenie poprzedniego montowania obrazu..."
            )
            try? FileManager.default.removeItem(at: mountURL)
        }
        if FileManager.default.fileExists(atPath: imageURL.path) {
            try? FileManager.default.removeItem(at: imageURL)
        }
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)

        let imageSizeGB = calculateLegacyImageSizeGB(from: distributionURL.deletingLastPathComponent())
        emit(
            percent: 0.12,
            status: "Tworzenie tymczasowego obrazu legacy",
            logLine: "legacy-assembly create-image size=\(imageSizeGB)g path=\(imageURL.path)"
        )

        try runCommand(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "create",
                "-fs", "HFS+",
                "-layout", "SPUD",
                "-size", "\(imageSizeGB)g",
                "-volname", "macUSBLegacyInstaller",
                "-ov",
                imageURL.path
            ]
        )

        try runCommand(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                imageURL.path,
                "-noverify",
                "-nobrowse",
                "-mountpoint", mountURL.path
            ]
        )

        defer {
            _ = detachDiskImageWithRetry(
                mountURL: mountURL,
                statusText: "Zamykanie tymczasowego obrazu..."
            )
            try? FileManager.default.removeItem(at: mountURL)
            try? FileManager.default.removeItem(at: imageURL)
        }

        let installerEnvironment = ProcessInfo.processInfo.environment.merging(["CM_BUILD": "CM_BUILD"]) { current, _ in current }
        emit(
            percent: 0.15,
            status: "Instalowanie składników systemu...",
            logLine: "legacy-assembly installer start dist=\(effectiveDistributionURL.path) target=\(mountURL.path)"
        )

        try runInstallerProcess(
            installerInputURL: effectiveDistributionURL,
            targetPath: mountURL.path,
            statusText: "Instalowanie składników systemu...",
            environment: installerEnvironment
        )

        guard let mountedInstallerURL = locateInstallerApp(onMountedVolume: mountURL) else {
            throw NSError(
                domain: "macUSBHelper",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Nie znaleziono aplikacji instalatora na tymczasowym obrazie legacy."]
            )
        }

        let destinationURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(request.expectedAppName, isDirectory: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        emit(
            percent: 0.90,
            status: "Kończenie przygotowania instalatora...",
            logLine: "legacy-assembly copy app source=\(mountedInstallerURL.path) destination=\(destinationURL.path)"
        )
        try runCommand(
            executable: "/usr/bin/ditto",
            arguments: [mountedInstallerURL.path, destinationURL.path]
        )

        emit(
            percent: 0.94,
            status: "Instalator gotowy",
            logLine: "legacy-assembly copy success destination=\(destinationURL.path)"
        )
        return destinationURL
    }

    private func createPatchedLegacyDistribution(
        from originalDistributionURL: URL,
        sessionRootDirectory: URL
    ) throws -> URL {
        let data = try Data(contentsOf: originalDistributionURL)
        guard var text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw NSError(
                domain: "macUSBHelper",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Nie udalo sie odczytac pliku .dist do patchowania."]
            )
        }

        let originalLength = text.count
        text = patchLegacyDistributionXML(text)
        if text == String(data: data, encoding: .utf8) {
            emit(
                percent: nil,
                status: "Instalowanie składników systemu...",
                logLine: "legacy-dist patch: brak zmian w tresci (pattern not matched) source=\(originalDistributionURL.path)"
            )
        } else {
            emit(
                percent: nil,
                status: "Instalowanie składników systemu...",
                logLine: "legacy-dist patch: zastosowano modyfikacje zgodnosci source=\(originalDistributionURL.path) chars_before=\(originalLength) chars_after=\(text.count)"
            )
        }

        let backupOriginalURL = sessionRootDirectory
            .appendingPathComponent("original_\(originalDistributionURL.lastPathComponent)")
        if FileManager.default.fileExists(atPath: backupOriginalURL.path) {
            try? FileManager.default.removeItem(at: backupOriginalURL)
        }
        try runCommand(
            executable: "/usr/bin/ditto",
            arguments: [originalDistributionURL.path, backupOriginalURL.path]
        )

        let patchedURL = originalDistributionURL
        guard let patchedData = text.data(using: .utf8) else {
            throw NSError(
                domain: "macUSBHelper",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Nie udalo sie zakodowac patchowanego pliku .dist do UTF-8."]
            )
        }
        try patchedData.write(to: patchedURL, options: .atomic)
        emit(
            percent: nil,
            status: "Instalowanie składników systemu...",
            logLine: "legacy-dist patch: backup original=\(backupOriginalURL.path) patched-in-place=\(patchedURL.path)"
        )
        return patchedURL
    }

    private func patchLegacyDistributionXML(_ xml: String) -> String {
        var patched = xml

        patched = regexReplace(
            in: patched,
            pattern: #"\s+hostArchitectures="[^"]*""#,
            template: ""
        )
        patched = regexReplace(
            in: patched,
            pattern: #"<installation-check\b[^>]*script="[^"]*"[^>]*/>"#,
            template: #"<installation-check script="return true;"/>"#
        )

        return patched
    }

    private func regexReplace(in text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    func runInstallerAndLocateApp(
        packageURL: URL,
        applyLegacyCompatibilityEnvironment: Bool = false
    ) throws -> URL {
        let environment: [String: String]?
        if applyLegacyCompatibilityEnvironment {
            environment = ProcessInfo.processInfo.environment.merging(["CM_BUILD": "CM_BUILD"]) { current, _ in current }
            emit(
                percent: nil,
                status: "Instalowanie składników systemu...",
                logLine: "legacy-assembly compatibility: ustawiono CM_BUILD dla \(packageURL.lastPathComponent)"
            )
        } else {
            environment = nil
        }

        try runInstallerProcess(
            installerInputURL: packageURL,
            targetPath: "/",
            statusText: "Instalowanie składników systemu...",
            environment: environment
        )

        guard let appURL = locateInstalledInstallerApp() else {
            throw NSError(
                domain: "macUSBHelper",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Nie znaleziono zbudowanej aplikacji instalatora."]
            )
        }

        return appURL
    }

    func rewriteInstallerOwnershipToRequesterIfNeeded(installerAppURL: URL) throws {
        let requesterUID = uid_t(request.requesterUID)
        guard requesterUID > 0 else {
            emit(
                percent: nil,
                status: "Kończenie przygotowania instalatora...",
                logLine: "assembly ownership: pomijam zmiane własności (brak requesterUID)"
            )
            return
        }
        guard let userRecord = getpwuid(requesterUID) else {
            throw NSError(
                domain: "macUSBHelper",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Nie udało się odczytać danych konta dla UID \(request.requesterUID)."]
            )
        }

        let requesterGID = userRecord.pointee.pw_gid
        emit(
            percent: 0.93,
            status: "Ustawianie własności instalatora...",
            logLine: "assembly ownership: chown -R \(requesterUID):\(requesterGID) \(installerAppURL.path)"
        )
        try runCommand(
            executable: "/usr/sbin/chown",
            arguments: ["-R", "\(requesterUID):\(requesterGID)", installerAppURL.path]
        )
        emit(
            percent: nil,
            status: "Ustawianie własności instalatora...",
            logLine: "assembly ownership: zakonczono dla \(installerAppURL.path)"
        )
    }

    private func runInstallerProcess(
        installerInputURL: URL,
        targetPath: String,
        statusText: String,
        environment: [String: String]?
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        process.arguments = ["-pkg", installerInputURL.path, "-target", targetPath, "-verboseR"]
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        stateQueue.sync {
            activeProcess = process
        }

        try process.run()
        let handle = pipe.fileHandleForReading
        var buffer = Data()
        let progressQueue = DispatchQueue(label: "macUSB.helper.downloaderAssembly.installerProgress")
        var targetProgress = 0.10
        var displayedProgress = 0.10
        var smoothingStopped = false
        let smoothingTimer = DispatchSource.makeTimerSource(queue: progressQueue)
        smoothingTimer.schedule(deadline: .now() + .milliseconds(120), repeating: .milliseconds(120))
        smoothingTimer.setEventHandler { [weak self] in
            guard let self else { return }
            guard !smoothingStopped else { return }
            let clampedTarget = min(max(targetProgress, 0.10), 0.82)
            let visibleTarget = max(0.10, clampedTarget - 0.003)
            guard displayedProgress < visibleTarget else { return }
            displayedProgress = min(visibleTarget, displayedProgress + 0.0045)
            self.emit(percent: displayedProgress, status: statusText)
        }
        smoothingTimer.resume()
        defer {
            progressQueue.sync {
                smoothingStopped = true
            }
            smoothingTimer.setEventHandler {}
            smoothingTimer.cancel()
        }

        while true {
            let chunk = handle.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)
            drainOutputLines(from: &buffer) { [weak self] line in
                self?.emitInstallerLine(line, statusText: statusText) { scaledProgress in
                    progressQueue.sync {
                        targetProgress = max(targetProgress, min(max(scaledProgress, 0.10), 0.82))
                    }
                }
            }
            try throwIfCancelled()
        }

        if !buffer.isEmpty,
           let tailLine = String(data: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !tailLine.isEmpty {
            emitInstallerLine(tailLine, statusText: statusText) { scaledProgress in
                progressQueue.sync {
                    targetProgress = max(targetProgress, min(max(scaledProgress, 0.10), 0.82))
                }
            }
        }

        process.waitUntilExit()
        stateQueue.sync {
            activeProcess = nil
        }
        try throwIfCancelled()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "macUSBHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Polecenie installer zakonczone bledem (\(process.terminationStatus))."]
            )
        }
        emit(percent: 0.82, status: statusText)
    }

    private func locateInstallerPackage(in mountedDiskImageURL: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: mountedDiskImageURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw NSError(
                domain: "macUSBHelper",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Nie udalo sie przeszukac zamontowanego obrazu .dmg."]
            )
        }

        var candidates: [URL] = []
        for case let candidate as URL in enumerator {
            guard candidate.pathExtension.caseInsensitiveCompare("pkg") == .orderedSame else {
                continue
            }
            candidates.append(candidate)
        }

        guard !candidates.isEmpty else {
            throw NSError(
                domain: "macUSBHelper",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "W obrazie .dmg nie znaleziono pakietu .pkg."]
            )
        }

        if let preferred = candidates.first(where: { $0.lastPathComponent.lowercased().contains("install") }) {
            return preferred
        }
        return candidates.sorted { lhs, rhs in lhs.path.count < rhs.path.count }.first!
    }

    private func locateInstallerApp(onMountedVolume mountURL: URL) -> URL? {
        let canonicalApplications = mountURL.appendingPathComponent("Applications", isDirectory: true)
        let fusedApplications = URL(fileURLWithPath: mountURL.path + "Applications", isDirectory: true)

        let candidates = [canonicalApplications, fusedApplications]
        for applicationsURL in candidates {
            let expected = applicationsURL.appendingPathComponent(request.expectedAppName, isDirectory: true)
            if FileManager.default.fileExists(atPath: expected.path) {
                return expected
            }
            if let found = newestInstallerApp(in: applicationsURL) {
                return found
            }
        }
        return nil
    }

    private func newestInstallerApp(in applicationsURL: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: applicationsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let installers = entries.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasPrefix("install macos") && name.hasSuffix(".app")
        }

        return installers.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    private func calculateLegacyImageSizeGB(from payloadDirectory: URL) -> Int {
        let requiredBytes = directorySizeBytes(at: payloadDirectory)
        let requiredGB = Int(ceil(Double(requiredBytes) / 1_000_000_000.0))
        return max(16, requiredGB + 4)
    }

    private func uniqueCollisionSafeURL(
        in directoryURL: URL,
        preferredFileName: String
    ) -> URL {
        let preferredURL = directoryURL.appendingPathComponent(preferredFileName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let baseName = (preferredFileName as NSString).deletingPathExtension
        let ext = (preferredFileName as NSString).pathExtension

        for index in 2...999 {
            let suffixName = ext.isEmpty
                ? "\(baseName) \(index)"
                : "\(baseName) \(index).\(ext)"
            let candidateURL = directoryURL.appendingPathComponent(suffixName, isDirectory: true)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directoryURL.appendingPathComponent("\(UUID().uuidString)-\(preferredFileName)", isDirectory: true)
    }

    private func directorySizeBytes(at rootURL: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else {
                continue
            }
            total += Int64(size)
        }
        return total
    }
    func locateInstalledInstallerApp() -> URL? {
        let expectedURL = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(request.expectedAppName, isDirectory: true)
        if FileManager.default.fileExists(atPath: expectedURL.path) {
            return expectedURL
        }

        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: applicationsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let installers = candidates.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasPrefix("install macos") && name.hasSuffix(".app")
        }

        return installers.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }
    func emitInstallerLine(
        _ rawLine: String,
        statusText: String? = nil,
        onScaledPercent: ((Double) -> Void)? = nil
    ) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let resolvedStatusText = statusText ?? "Instalowanie składników systemu..."

        if let percent = parseInstallerPercent(from: line) {
            let normalized = min(max(percent / 100.0, 0), 1)
            let scaled = 0.10 + (normalized * 0.72)
            onScaledPercent?(scaled)
            emit(percent: nil, status: resolvedStatusText, logLine: line)
        } else {
            emit(percent: nil, status: resolvedStatusText, logLine: line)
        }
    }
    func parseInstallerPercent(from line: String) -> Double? {
        let pattern = #"([0-9]{1,3}(?:\.[0-9]+)?)\%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 1
        else {
            return nil
        }
        let value = nsLine.substring(with: match.range(at: 1))
        return Double(value)
    }
    func drainOutputLines(from buffer: inout Data, consume: (String) -> Void) {
        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            if let line = String(data: lineData, encoding: .utf8) {
                consume(line)
            }
            buffer.removeSubrange(0...newlineRange.lowerBound)
        }
    }
    func runCommand(executable: String, arguments: [String], environment: [String: String]? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "macUSBHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Polecenie \(executable) zakonczone bledem (\(process.terminationStatus))."]
            )
        }
    }
    func emit(percent: Double?, status: String, logLine: String? = nil) {
        let payload = DownloaderAssemblyProgressPayload(
            workflowID: workflowID,
            percent: percent ?? 0,
            statusText: status,
            logLine: logLine
        )
        sendProgress(payload)
    }
    func throwIfCancelled() throws {
        let cancelled = stateQueue.sync { isCancelled }
        if cancelled {
            throw NSError(
                domain: "macUSBHelper",
                code: NSUserCancelledError,
                userInfo: [NSLocalizedDescriptionKey: "Operacja budowania instalatora zostala anulowana."]
            )
        }
    }
}
