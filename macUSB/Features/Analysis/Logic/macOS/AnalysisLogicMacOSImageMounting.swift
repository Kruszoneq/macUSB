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
            self.log("Found legacy installer path: \(installerURL.path)")

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
            self.log("Legacy 'Install Mac OS X' installer path not found in: \(mountURL.path)")
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
        self.log("macOS installer app validation from image (\(context)): \(inspection.logSummary)")

        guard let (name, rawVersion, appURL) = inspection.appInfo else {
            if let legacyInfo = mountedLegacyInstallerInfoIfCompatible(
                inspection: inspection,
                mountedSystemVersion: mountedSystemVersion,
                context: context
            ) {
                self.log("Accepted legacy macOS installer from image based on mounted SystemVersion.plist: name=\(legacyInfo.name), version=\(legacyInfo.rawVersion), mountedSystemVersion=\(mountedSystemVersion ?? "none")")
                return (legacyInfo.name, legacyInfo.rawVersion, legacyInfo.appURL, mountPoint)
            }

            self.logError("Rejected image .app as a macOS installer: \(inspection.decisionReason) [path=\(installerURL.path)]")
            return nil
        }

        self.log("Recognized valid macOS installer from image: name=\(name), version=\(rawVersion)")
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
            self.log("Found legacy SystemVersion.plist, but the .app name does not look like a macOS installer (\(context)): \(inspection.appURL.path)")
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
            self.logError("Failed to start hdiutil info: \(error.localizedDescription)")
            return nil
        }
        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if task.terminationStatus != 0 {
            let stderrText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stderrText.isEmpty {
                self.logError("hdiutil info failed (exit code \(task.terminationStatus)).")
            } else {
                self.logError("hdiutil info failed: \(stderrText)")
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
        self.log("Attaching image (DMG/ISO/CDR)")
        if detectPreMountedSource,
           let mountPoint = mountedPathForAlreadyAttachedImage(sourceURL: dmgUrl) {
            self.log("Selected image .\(dmgUrl.pathExtension.lowercased()) is already mounted in macOS: \(mountPoint)")
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
            self.logError("Failed to start hdiutil attach: \(error.localizedDescription)")
            if detectPreMountedSource,
               let mountPoint = mountedPathForAlreadyAttachedImage(sourceURL: dmgUrl) {
                self.log("Source image was already mounted after attach launch failed: \(mountPoint)")
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
                self.logError("hdiutil attach failed (exit code \(task.terminationStatus)).")
            } else {
                self.logError("hdiutil attach failed: \(stderrText)")
            }
            if detectPreMountedSource,
               let mountPoint = mountedPathForAlreadyAttachedImage(sourceURL: dmgUrl) {
                self.log("Source image was already mounted after attach failed: \(mountPoint)")
                return (mountedReadInfo: nil, sourceAlreadyMountedPath: mountPoint, mountedImagePath: nil)
            }
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let entities = plist["system-entities"] as? [[String: Any]] else {
            self.logError("Failed to read image information")
            if detectPreMountedSource,
               let mountPoint = mountedPathForAlreadyAttachedImage(sourceURL: dmgUrl) {
                self.log("Source image was already mounted after plist read failed: \(mountPoint)")
                return (mountedReadInfo: nil, sourceAlreadyMountedPath: mountPoint, mountedImagePath: nil)
            }
            return nil
        }
        self.log("Processing hdiutil attach results (\(entities.count) entities)")
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

                self.log("Mounted image: \(mp) [id: \(mountId)]")
                let mUrl = URL(fileURLWithPath: mp)
                let mountedSystemVersion = mountedSystemUserVisibleVersion(from: mUrl)
                if let mountedSystemVersion {
                    self.log("Read system version from mounted image: \(mountedSystemVersion)")
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
                        self.log("No .app bundle found in mounted image: \(mp)")
                    } else {
                        self.log("Found .app bundles in mounted image (\(appCandidates.count)). Checking deterministically by name.")
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
                        self.log("No .app bundle in mounted image passed macOS installer validation: \(mp)")
                    }
                } else {
                    self.log("Failed to read mounted image directory: \(mp)")
                }
            }
        }
        self.log("Attempted to attach the image and find a valid macOS installer .app, but none was found.")
        if let firstMountedImagePath {
            self.log("No macOS installer .app in mounted image. Keeping mount point for further analysis: \(firstMountedImagePath)")
            return (mountedReadInfo: nil, sourceAlreadyMountedPath: nil, mountedImagePath: firstMountedImagePath)
        }
        self.logError("Failed to read image information")
        return nil
    }

    func mountImageForPPC(dmgUrl: URL) -> String? {
        self.log("Attaching image (PPC)", workflow: .ppc)
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", dmgUrl.path, "-plist", "-nobrowse", "-readonly"]
        let pipe = Pipe(); task.standardOutput = pipe; try? task.run(); task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let entities = plist["system-entities"] as? [[String: Any]] else {
            self.logError("Failed to attach image (PPC)", workflow: .ppc)
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
                self.log("Mounted image (PPC): \(mp) [id: \(mountId)]", workflow: .ppc)
                return mp
            }
        }
        self.logError("Failed to attach image (PPC)", workflow: .ppc)
        return nil
    }
}
