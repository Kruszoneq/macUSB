import Foundation

extension AnalysisLogic {
    func readWindowsMetadata(fromMountPath mountPath: String, sourceURL: URL) -> WindowsImageMetadata? {
        let mountURL = URL(fileURLWithPath: mountPath, isDirectory: true)
        let fm = FileManager.default

        func exists(_ relativePath: String) -> Bool {
            let path = mountURL.appendingPathComponent(relativePath).path
            return fm.fileExists(atPath: path)
        }

        var evidence: [String] = []

        let hasInstallWIM = exists("sources/install.wim")
        let hasInstallESD = exists("sources/install.esd")
        let hasInstallSWM = exists("sources/install.swm")
        if hasInstallWIM { evidence.append("sources/install.wim") }
        if hasInstallESD { evidence.append("sources/install.esd") }
        if hasInstallSWM { evidence.append("sources/install.swm") }

        let hasI386 = exists("I386")
        if hasI386 { evidence.append("I386") }

        let rootEntries = (try? fm.contentsOfDirectory(atPath: mountPath)) ?? []
        let win51Markers = rootEntries
            .filter { $0.uppercased().hasPrefix("WIN51") }
            .sorted()
        if !win51Markers.isEmpty {
            evidence.append("win51-markers:\(win51Markers.joined(separator: ","))")
        }

        let idwbinfoText = readWindowsTextFile(
            fromMountPath: mountPath,
            relativePath: "sources/idwbinfo.txt",
            maxBytes: 32_000
        )
        let idwbinfoFields = parseWindowsIniLikeFields(idwbinfoText)
        if !idwbinfoFields.isEmpty {
            evidence.append("sources/idwbinfo.txt")
        }
        let buildBranch = idwbinfoFields["buildbranch"]?.lowercased()
        let buildArchRaw = idwbinfoFields["buildarch"]?.lowercased()
        if let buildBranch { evidence.append("branch:\(buildBranch)") }
        if let buildArchRaw { evidence.append("buildarch:\(buildArchRaw)") }

        let cversionText = readWindowsTextFile(
            fromMountPath: mountPath,
            relativePath: "sources/cversion.ini",
            maxBytes: 8_000
        )
        let cversionFields = parseWindowsIniLikeFields(cversionText)
        let cversionMinClient = cversionFields["minclient"]
        let cversionMinServer = cversionFields["minserver"]
        if cversionMinClient != nil || cversionMinServer != nil {
            evidence.append("sources/cversion.ini")
        }
        if let cversionMinClient {
            evidence.append("cversion-minclient:\(cversionMinClient)")
        }
        if let cversionMinServer {
            evidence.append("cversion-minserver:\(cversionMinServer)")
        }

        let hasEFIDirectory = exists("efi")
        let hasBootMgrEFI = exists("bootmgr.efi")
        let hasCdBootEFI = exists("efi/microsoft/boot/cdboot.efi")
        let hasBootx64EFI = exists("efi/boot/bootx64.efi")
        let hasBootaa64EFI = exists("efi/boot/bootaa64.efi")

        var efiEvidence: [String] = []
        if hasEFIDirectory { efiEvidence.append("efi/") }
        if hasBootMgrEFI { efiEvidence.append("bootmgr.efi") }
        if hasCdBootEFI { efiEvidence.append("efi/microsoft/boot/cdboot.efi") }
        if hasBootx64EFI { efiEvidence.append("efi/boot/bootx64.efi") }
        if hasBootaa64EFI { efiEvidence.append("efi/boot/bootaa64.efi") }

        let hasEFI = hasEFIDirectory && (hasBootMgrEFI || hasCdBootEFI || hasBootx64EFI || hasBootaa64EFI)
        let efiStatus = WindowsEFIStatus(hasEFI: hasEFI, evidence: efiEvidence.sorted())
        evidence.append("efi:\(hasEFI ? "yes" : "no")")

        let hasWindowsSignals =
            hasInstallWIM ||
            hasInstallESD ||
            hasInstallSWM ||
            hasI386 ||
            !win51Markers.isEmpty ||
            !idwbinfoFields.isEmpty

        guard hasWindowsSignals else {
            self.log("Brak wystarczających sygnałów Windows w ISO: \(sourceURL.lastPathComponent)")
            return nil
        }

        let volumeName = mountURL.lastPathComponent
        evidence.append("volume:\(volumeName)")

        return WindowsImageMetadata(
            volumeName: volumeName,
            buildBranch: buildBranch,
            buildArchRaw: buildArchRaw,
            hasI386: hasI386,
            win51Markers: win51Markers,
            hasInstallWIM: hasInstallWIM,
            hasInstallESD: hasInstallESD,
            hasInstallSWM: hasInstallSWM,
            cversionMinClient: cversionMinClient,
            cversionMinServer: cversionMinServer,
            sourceFileName: sourceURL.lastPathComponent,
            efiStatus: efiStatus,
            evidence: Array(Set(evidence)).sorted()
        )
    }

    private func readWindowsTextFile(
        fromMountPath mountPath: String,
        relativePath: String,
        maxBytes: Int = 64_000
    ) -> String? {
        let path = URL(fileURLWithPath: mountPath)
            .appendingPathComponent(relativePath)
            .path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maxBytes)
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1250)
            ?? String(data: data, encoding: .ascii)
    }

    private func parseWindowsIniLikeFields(_ text: String?) -> [String: String] {
        guard let text else { return [:] }
        var fields: [String: String] = [:]
        text.split(whereSeparator: \.isNewline).forEach { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("["), !line.hasPrefix(";"), !line.hasPrefix("#") else { return }
            guard let equals = line.firstIndex(of: "=") else { return }
            let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            fields[key] = value
        }
        return fields
    }
}
