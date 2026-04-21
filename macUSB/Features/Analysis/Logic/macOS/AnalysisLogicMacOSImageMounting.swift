import Foundation

extension AnalysisLogic {
    private func readLegacyInstallMacOSXInfo(from mountURL: URL) -> (String, String, URL)? {
        let legacyInstallers = [
            "Install Mac OS X",
            "Install Mac OS X.app"
        ]

        var foundLegacyPath = false
        for installerName in legacyInstallers {
            let installerURL = mountURL.appendingPathComponent(installerName, isDirectory: true)
            let plistURL = installerURL.appendingPathComponent("Contents/Info.plist")
            guard FileManager.default.fileExists(atPath: plistURL.path) else {
                continue
            }

            foundLegacyPath = true
            self.log("Znaleziono legacy installer path: \(installerURL.path)")
            self.log("Odczyt Info.plist (legacy): \(plistURL.path)")

            guard let data = try? Data(contentsOf: plistURL),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                self.logError("Nie udało się odczytać Info.plist (legacy): \(plistURL.path)")
                continue
            }

            let name = (dict["CFBundleDisplayName"] as? String) ?? installerURL.lastPathComponent
            let version = (dict["CFBundleShortVersionString"] as? String) ?? "?"
            self.log("Odczytano Info.plist (legacy): name=\(name), version=\(version)")
            return (name, version, installerURL)
        }

        if !foundLegacyPath {
            self.log("Nie znaleziono legacy path instalatora 'Install Mac OS X' w: \(mountURL.path)")
        }

        return nil
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
                if let (legacyName, legacyVersion, legacyInstallerURL) = self.readLegacyInstallMacOSXInfo(from: mUrl) {
                    self.log("Rozpoznano instalator legacy z obrazu: name=\(legacyName), version=\(legacyVersion)")
                    return (mountedReadInfo: (legacyName, legacyVersion, legacyInstallerURL, mp), sourceAlreadyMountedPath: nil, mountedImagePath: mp)
                }
                let dirContents = try? FileManager.default.contentsOfDirectory(at: mUrl, includingPropertiesForKeys: nil)
                if let item = dirContents?.first(where: { $0.pathExtension == "app" }) {
                    let plistUrl = item.appendingPathComponent("Contents/Info.plist")
                    self.log("Odczyt Info.plist: \(plistUrl.path)")
                    if let d = try? Data(contentsOf: plistUrl), let dict = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
                        let name = (dict["CFBundleDisplayName"] as? String) ?? item.lastPathComponent
                        let ver = (dict["CFBundleShortVersionString"] as? String) ?? "?"
                        self.log("Odczytano Info.plist z obrazu: name=\(name), version=\(ver)")
                        return (mountedReadInfo: (name, ver, item, mp), sourceAlreadyMountedPath: nil, mountedImagePath: mp)
                    } else {
                        self.logError("Nie udało się odczytać Info.plist z obrazu: \(plistUrl.path)")
                    }
                } else {
                    self.log("Nie znaleziono pakietu .app w zamontowanym obrazie: \(mp)")
                    if let names = dirContents?.map({ $0.lastPathComponent }).prefix(10) {
                        self.log("Zawartość katalogu (\(mp)) [pierwsze 10]: \(names.joined(separator: ", "))")
                    }
                }
            }
        }
        self.log("Próbowano zamontować obraz i znaleźć pakiet .app oraz plik Info.plist, ale nie zostały odnalezione.")
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
