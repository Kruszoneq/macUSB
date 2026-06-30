import Foundation

extension AnalysisLogic {
    private typealias MountedInstallerReadInfo = (name: String, rawVersion: String, appURL: URL, mountPoint: String)

    private var legacyInstallMacOSXCandidateNames: [String] {
        [
            "Install Mac OS X",
            "Install Mac OS X.app"
        ]
    }

    private func readLegacyInstallMacOSXInfo(
        from mountURL: URL,
        mountPoint: String,
        mountedSystemVersion: String?
    ) -> MountedInstallerReadInfo? {
        var foundLegacyPath = false
        for installerName in legacyInstallMacOSXCandidateNames {
            let installerURL = mountURL.appendingPathComponent(installerName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: installerURL.path) else {
                continue
            }

            foundLegacyPath = true
            self.log("Znaleziono legacy installer path: \(installerURL.path)")

            if let installerInfo = validatedMountedInstallerInfo(
                from: installerURL,
                mountPoint: mountPoint,
                mountedSystemVersion: mountedSystemVersion,
                context: "legacy_path"
            ) {
                return installerInfo
            }
        }

        if !foundLegacyPath {
            self.log("Nie znaleziono legacy path instalatora 'Install Mac OS X' w: \(mountURL.path)")
        }

        return nil
    }

    private func validatedMountedInstallerInfo(
        from installerURL: URL,
        mountPoint: String,
        mountedSystemVersion: String?,
        context: String
    ) -> MountedInstallerReadInfo? {
        let inspection = inspectMacOSInstallerApp(at: installerURL)
        self.log("Walidacja aplikacji instalatora macOS z obrazu (\(context)): \(inspection.logSummary)")

        guard let (name, rawVersion, appURL) = inspection.appInfo else {
            if let legacyInfo = mountedLegacyInstallerInfoIfCompatible(
                inspection: inspection,
                mountedSystemVersion: mountedSystemVersion,
                context: context
            ) {
                self.log("Zaakceptowano legacy instalator macOS z obrazu na podstawie zamontowanego SystemVersion.plist: name=\(legacyInfo.name), version=\(legacyInfo.rawVersion), mountedSystemVersion=\(mountedSystemVersion ?? "brak")")
                return (legacyInfo.name, legacyInfo.rawVersion, legacyInfo.appURL, mountPoint)
            }

            self.logError("Odrzucono aplikację .app w obrazie jako instalator macOS: \(inspection.decisionReason) [path=\(installerURL.path)]")
            return nil
        }

        self.log("Rozpoznano poprawny instalator macOS z obrazu: name=\(name), version=\(rawVersion)")
        return (name, rawVersion, appURL, mountPoint)
    }

    private func mountedLegacyInstallerInfoIfCompatible(
        inspection: MacOSInstallerAppInspection,
        mountedSystemVersion: String?,
        context: String
    ) -> (name: String, rawVersion: String, appURL: URL)? {
        guard inspection.decisionReason == "missing_required_installer_payload" ||
                inspection.decisionReason == "installesd_without_restore_legacy_metadata" else {
            return nil
        }
        guard isMountedLegacyMacOSVersion(mountedSystemVersion),
              let name = inspection.displayName,
              let rawVersion = inspection.rawVersion else {
            return nil
        }

        let candidateText = "\(name) \(inspection.appURL.lastPathComponent)".lowercased()
        guard candidateText.contains("install") ||
                candidateText.contains("mac os x") ||
                candidateText.contains("tiger") ||
                candidateText.contains("leopard") ||
                candidateText.contains("panther") else {
            self.log("Znaleziono legacy SystemVersion.plist, ale nazwa .app nie wygląda jak instalator macOS (\(context)): \(inspection.appURL.path)")
            return nil
        }

        return (name, rawVersion, inspection.appURL)
    }

    private func isMountedLegacyMacOSVersion(_ version: String?) -> Bool {
        guard let version else { return false }
        return version.hasPrefix("10.3") ||
            version.hasPrefix("10.4") ||
            version.hasPrefix("10.5") ||
            version.hasPrefix("10.6")
    }

    private func mountedSystemUserVisibleVersion(from mountURL: URL) -> String? {
        let sysVerPlist = mountURL.appendingPathComponent("System/Library/CoreServices/SystemVersion.plist")
        guard let data = try? Data(contentsOf: sysVerPlist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let userVisible = dict["ProductUserVisibleVersion"] as? String else {
            return nil
        }
        return userVisible
    }

    private func rootAppCandidates(in mountURL: URL) -> [URL]? {
        guard let dirContents = try? FileManager.default.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: nil) else {
            return nil
        }

        let legacyCandidatePaths = Set(
            legacyInstallMacOSXCandidateNames.map {
                mountURL.appendingPathComponent($0, isDirectory: true).standardizedFileURL.path
            }
        )

        return dirContents
            .filter { $0.pathExtension.lowercased() == "app" }
            .filter { !legacyCandidatePaths.contains($0.standardizedFileURL.path) }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    private func normalizedImagePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func mountedPathForAlreadyAttachedImage(sourceURL: URL) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["info", "-plist"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            self.logError("Nie udało się uruchomić hdiutil info: \(error.localizedDescription)")
            return nil
        }
        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if task.terminationStatus != 0 {
            let stderrText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stderrText.isEmpty {
                self.logError("hdiutil info zakończył się błędem (kod \(task.terminationStatus)).")
            } else {
                self.logError("hdiutil info zakończył się błędem: \(stderrText)")
            }
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: outputData, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return nil
        }

        let sourcePath = normalizedImagePath(sourceURL.path)
        for image in images {
            guard let imagePath = image["image-path"] as? String else { continue }
            guard normalizedImagePath(imagePath) == sourcePath else { continue }
            guard let entities = image["system-entities"] as? [[String: Any]],
                  let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
                continue
            }
            return mountPoint
        }

        return nil
    }

    func mountAndReadInfo(dmgUrl: URL, detectPreMountedSource: Bool = false) -> (mountedReadInfo: (String, String, URL, String)?, sourceAlreadyMountedPath: String?, mountedImagePath: String?)? {
        self.log("Montowanie obrazu (DMG/ISO/CDR)")
        if detectPreMountedSource,
           let mountPoint = mountedPathForAlreadyAttachedImage(sourceURL: dmgUrl) {
            self.log("Wybrany obraz .\(dmgUrl.pathExtension.lowercased()) jest już zamontowany w systemie: \(mountPoint)")
            return (mountedReadInfo: nil, sourceAlreadyMountedPath: mountPoint, mountedImagePath: nil)
        }

        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", dmgUrl.path, "-plist", "-nobrowse", "-readonly"]
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            self.logError("Nie udało się uruchomić hdiutil attach: \(error.localizedDescription)")
            if detectPreMountedSource,
               let mountPoint = mountedPathForAlreadyAttachedImage(sourceURL: dmgUrl) {
                self.log("Po błędzie uruchomienia attach wykryto już zamontowany obraz źródłowy: \(mountPoint)")
                return (mountedReadInfo: nil, sourceAlreadyMountedPath: mountPoint, mountedImagePath: nil)
            }
            return nil
        }
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if task.terminationStatus != 0 {
            if stderrText.isEmpty {
                self.logError("hdiutil attach zakończył się błędem (kod \(task.terminationStatus)).")
            } else {
                self.logError("hdiutil attach zakończył się błędem: \(stderrText)")
            }
            if detectPreMountedSource,
               let mountPoint = mountedPathForAlreadyAttachedImage(sourceURL: dmgUrl) {
                self.log("Po błędzie attach wykryto już zamontowany obraz źródłowy: \(mountPoint)")
                return (mountedReadInfo: nil, sourceAlreadyMountedPath: mountPoint, mountedImagePath: nil)
            }
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let entities = plist["system-entities"] as? [[String: Any]] else {
            self.logError("Nie udało się odczytać informacji z obrazu")
            if detectPreMountedSource,
               let mountPoint = mountedPathForAlreadyAttachedImage(sourceURL: dmgUrl) {
                self.log("Po nieudanym odczycie plist wykryto już zamontowany obraz źródłowy: \(mountPoint)")
                return (mountedReadInfo: nil, sourceAlreadyMountedPath: mountPoint, mountedImagePath: nil)
            }
            return nil
        }
        self.log("Przetwarzanie wyników hdiutil attach (\(entities.count) encji)")
        var firstMountedImagePath: String?
        for e in entities {
            if let mp = e["mount-point"] as? String {
                if firstMountedImagePath == nil {
                    firstMountedImagePath = mp
                }
                let devEntry = (e["dev-entry"] as? String) ?? (e["devname"] as? String)
                var mountId = "unknown"
                if let dev = devEntry {
                    let bsd = URL(fileURLWithPath: dev).lastPathComponent // e.g. disk9s1
                    if let range = bsd.range(of: #"s\d+$"#, options: .regularExpression) {
                        mountId = String(bsd[..<range.lowerBound]) // e.g. disk9
                    } else {
                        mountId = bsd // e.g. disk9
                    }
                }

                self.log("Zamontowano obraz: \(mp) [id: \(mountId)]")
                let mUrl = URL(fileURLWithPath: mp)
                let mountedSystemVersion = mountedSystemUserVisibleVersion(from: mUrl)
                if let mountedSystemVersion {
                    self.log("Odczytano wersję systemu z zamontowanego obrazu: \(mountedSystemVersion)")
                }

                if let installerInfo = self.readLegacyInstallMacOSXInfo(
                    from: mUrl,
                    mountPoint: mp,
                    mountedSystemVersion: mountedSystemVersion
                ) {
                    return (mountedReadInfo: installerInfo, sourceAlreadyMountedPath: nil, mountedImagePath: mp)
                }

                if let appCandidates = rootAppCandidates(in: mUrl) {
                    if appCandidates.isEmpty {
                        self.log("Nie znaleziono pakietu .app w zamontowanym obrazie: \(mp)")
                    } else {
                        self.log("Znaleziono pakiety .app w zamontowanym obrazie (\(appCandidates.count)). Sprawdzam deterministycznie według nazwy.")
                        for appCandidate in appCandidates {
                            if let installerInfo = validatedMountedInstallerInfo(
                                from: appCandidate,
                                mountPoint: mp,
                                mountedSystemVersion: mountedSystemVersion,
                                context: "root_app"
                            ) {
                                return (mountedReadInfo: installerInfo, sourceAlreadyMountedPath: nil, mountedImagePath: mp)
                            }
                        }
                        self.log("Żaden pakiet .app w zamontowanym obrazie nie przeszedł walidacji instalatora macOS: \(mp)")
                    }
                } else {
                    self.log("Nie udało się odczytać zawartości katalogu zamontowanego obrazu: \(mp)")
                }
            }
        }
        self.log("Próbowano zamontować obraz i znaleźć poprawny pakiet instalatora macOS .app, ale nie został odnaleziony.")
        if let firstMountedImagePath {
            self.log("Brak instalatora macOS .app na zamontowanym obrazie. Zachowuję mount-point do dalszej analizy: \(firstMountedImagePath)")
            return (mountedReadInfo: nil, sourceAlreadyMountedPath: nil, mountedImagePath: firstMountedImagePath)
        }
        self.logError("Nie udało się odczytać informacji z obrazu")
        return nil
    }

    func mountImageForPPC(dmgUrl: URL) -> String? {
        self.log("Montowanie obrazu (PPC)")
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", dmgUrl.path, "-plist", "-nobrowse", "-readonly"]
        let pipe = Pipe(); task.standardOutput = pipe; try? task.run(); task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let entities = plist["system-entities"] as? [[String: Any]] else {
            self.logError("Nie udało się zamontować obrazu (PPC)")
            return nil
        }
        for e in entities {
            if let mp = e["mount-point"] as? String {
                let devEntry = (e["dev-entry"] as? String) ?? (e["devname"] as? String)
                var mountId = "unknown"
                if let dev = devEntry {
                    let bsd = URL(fileURLWithPath: dev).lastPathComponent
                    if let range = bsd.range(of: #"s\d+$"#, options: .regularExpression) {
                        mountId = String(bsd[..<range.lowerBound])
                    } else {
                        mountId = bsd
                    }
                }
                self.log("Zamontowano obraz (PPC): \(mp) [id: \(mountId)]")
                return mp
            }
        }
        self.logError("Nie udało się zamontować obrazu (PPC)")
        return nil
    }
}
