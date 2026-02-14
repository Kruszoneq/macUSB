import Foundation
import SwiftUI

extension UniversalInstallationView {
    func startCreationProcessEntry() {
        startCreationProcessWithHelper()
    }

    private func startCreationProcessWithHelper() {
        guard let drive = targetDrive else {
            errorMessage = String(localized: "Błąd: Nie wybrano dysku.")
            return
        }

        withAnimation(.easeInOut(duration: 0.4)) {
            isTabLocked = true
            isProcessing = true
        }

        processingTitle = String(localized: "Rozpoczynanie...")
        processingSubtitle = String(localized: "Przygotowywanie operacji...")
        isHelperWorking = false
        errorMessage = ""
        navigateToFinish = false
        helperOperationFailed = false
        stopUSBMonitoring()
        processingIcon = "lock.shield.fill"
        isCancelled = false
        helperProgressPercent = 0
        helperStageTitle = String(localized: "Przygotowanie")
        helperStatusText = String(localized: "Sprawdzanie gotowości helpera...")
        helperWriteSpeedText = "— MB/s"
        stopHelperWriteSpeedMonitoring()

        do {
            try preflightTargetVolumeWriteAccess(drive.url)
        } catch {
            withAnimation {
                isProcessing = false
                isHelperWorking = false
                isTabLocked = false
                startUSBMonitoring()
                stopHelperWriteSpeedMonitoring()
                errorMessage = error.localizedDescription
            }
            return
        }

        HelperServiceManager.shared.ensureReadyForPrivilegedWork { ready, failureReason in
            guard ready else {
                withAnimation {
                    isProcessing = false
                    isHelperWorking = false
                    isTabLocked = false
                    startUSBMonitoring()
                    stopHelperWriteSpeedMonitoring()
                    errorMessage = failureReason ?? String(localized: "Helper nie jest gotowy do pracy.")
                }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = try prepareHelperWorkflowRequest(for: drive)
                    DispatchQueue.main.async {
                        withAnimation {
                            isProcessing = false
                            isHelperWorking = true
                            helperProgressPercent = 0
                            helperStageTitle = String(localized: "Uruchamianie helpera")
                            helperStatusText = String(localized: "Nawiązywanie połączenia XPC...")
                        }

                        PrivilegedOperationClient.shared.startWorkflow(
                            request: request,
                            onEvent: { event in
                                guard event.workflowID == activeHelperWorkflowID else { return }
                                helperProgressPercent = max(helperProgressPercent, min(event.percent, 100))
                                helperStageTitle = event.stageTitle
                                helperStatusText = event.statusText
                            },
                            onCompletion: { result in
                                guard result.workflowID == activeHelperWorkflowID else { return }

                                activeHelperWorkflowID = nil
                                isHelperWorking = false
                                stopHelperWriteSpeedMonitoring()

                                if result.isUserCancelled || isCancelled {
                                    return
                                }

                                helperOperationFailed = !result.success

                                if !result.success, let errorMessageText = result.errorMessage {
                                    logError("Helper zakończył się błędem: \(errorMessageText)", category: "Installation")
                                }

                                withAnimation {
                                    navigateToFinish = true
                                }
                            },
                            onStartError: { message in
                                activeHelperWorkflowID = nil
                                logError("Start helper workflow nieudany: \(message)", category: "Installation")
                                withAnimation {
                                    isProcessing = false
                                    isHelperWorking = false
                                    isTabLocked = false
                                    startUSBMonitoring()
                                    stopHelperWriteSpeedMonitoring()
                                    errorMessage = message
                                }
                            },
                            onStarted: { workflowID in
                                activeHelperWorkflowID = workflowID
                                helperStageTitle = String(localized: "Rozpoczynanie...")
                                helperStatusText = String(localized: "Helper uruchamia pierwszy etap operacji uprzywilejowanych...")
                                startHelperWriteSpeedMonitoring(for: drive)
                                log("Uruchomiono helper workflow: \(workflowID)")
                            }
                        )
                    }
                } catch {
                    DispatchQueue.main.async {
                        withAnimation {
                            isProcessing = false
                            isHelperWorking = false
                            isTabLocked = false
                            startUSBMonitoring()
                            stopHelperWriteSpeedMonitoring()
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private func prepareHelperWorkflowRequest(for drive: USBDrive) throws -> HelperWorkflowRequestPayload {
        let fileManager = FileManager.default
        let requesterUID = Int(getuid())

        if !fileManager.fileExists(atPath: tempWorkURL.path) {
            try fileManager.createDirectory(at: tempWorkURL, withIntermediateDirectories: true)
        }

        let shouldPreformat = drive.needsFormatting && !isPPC
        let sourceIsMountedVolume = sourceAppURL.path.hasPrefix("/Volumes/")

        if isRestoreLegacy {
            let sourceESD = sourceAppURL.appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")
            guard fileManager.fileExists(atPath: sourceESD.path) else {
                throw NSError(
                    domain: "macUSB",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono pliku InstallESD.dmg.")]
                )
            }

            let targetESD = tempWorkURL.appendingPathComponent("InstallESD.dmg")
            if fileManager.fileExists(atPath: targetESD.path) {
                try fileManager.removeItem(at: targetESD)
            }
            try fileManager.copyItem(at: sourceESD, to: targetESD)

            return HelperWorkflowRequestPayload(
                workflowKind: .legacyRestore,
                systemName: systemName,
                sourcePath: targetESD.path,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: shouldPreformat,
                isCatalina: false,
                requiresApplicationPathArg: false,
                postInstallSourceAppPath: nil,
                requesterUID: requesterUID
            )
        }

        if isMavericks {
            let sourceImage = originalImageURL ?? sourceAppURL
            guard fileManager.fileExists(atPath: sourceImage.path) else {
                throw NSError(
                    domain: "macUSB",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono źródłowego pliku obrazu.")]
                )
            }

            let targetImage = tempWorkURL.appendingPathComponent("InstallESD.dmg")
            if fileManager.fileExists(atPath: targetImage.path) {
                try fileManager.removeItem(at: targetImage)
            }
            try fileManager.copyItem(at: sourceImage, to: targetImage)

            return HelperWorkflowRequestPayload(
                workflowKind: .mavericks,
                systemName: systemName,
                sourcePath: targetImage.path,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: shouldPreformat,
                isCatalina: false,
                requiresApplicationPathArg: false,
                postInstallSourceAppPath: nil,
                requesterUID: requesterUID
            )
        }

        if isPPC {
            let mountedVolumeSource = sourceAppURL.deletingLastPathComponent().path
            let mountedSourceAvailable = mountedVolumeSource.hasPrefix("/Volumes/") &&
            fileManager.fileExists(atPath: mountedVolumeSource)
            let restoreSource: String

            if let imageURL = originalImageURL, fileManager.fileExists(atPath: imageURL.path) {
                let sourceExt = imageURL.pathExtension.lowercased()

                // asr restore with --source=<file> accepts UDIF images.
                // ISO/CDR from legacy installers must go through mounted volume source.
                if (sourceExt == "iso" || sourceExt == "cdr"), mountedSourceAvailable {
                    restoreSource = mountedVolumeSource
                    log("PPC helper strategy: asr restore from mounted source (ISO/CDR) -> /Volumes/PPC", category: "Installation")
                } else {
                    let stagedImageURL = tempWorkURL.appendingPathComponent("PPC_\(imageURL.lastPathComponent)")
                    if fileManager.fileExists(atPath: stagedImageURL.path) {
                        try fileManager.removeItem(at: stagedImageURL)
                    }
                    try fileManager.copyItem(at: imageURL, to: stagedImageURL)
                    restoreSource = stagedImageURL.path
                    log("PPC helper strategy: asr restore from staged image -> /Volumes/PPC", category: "Installation")
                }
            } else if mountedSourceAvailable {
                restoreSource = mountedVolumeSource
                log("PPC helper strategy: asr restore from mounted source fallback -> /Volumes/PPC", category: "Installation")
            } else {
                throw NSError(
                    domain: "macUSB",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono źródła PPC do przywracania.")]
                )
            }

            log("PPC helper source: \(restoreSource)", category: "Installation")

            return HelperWorkflowRequestPayload(
                workflowKind: .ppc,
                systemName: systemName,
                sourcePath: restoreSource,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: false,
                isCatalina: false,
                requiresApplicationPathArg: false,
                postInstallSourceAppPath: nil,
                requesterUID: requesterUID
            )
        }

        var effectiveAppURL = sourceAppURL

        if isSierra {
            let destinationAppURL = tempWorkURL.appendingPathComponent(sourceAppURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationAppURL.path) {
                try fileManager.removeItem(at: destinationAppURL)
            }
            try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)

            let plistPath = destinationAppURL.appendingPathComponent("Contents/Info.plist").path
            let plutilTask = Process()
            plutilTask.launchPath = "/usr/bin/plutil"
            plutilTask.arguments = ["-replace", "CFBundleShortVersionString", "-string", "12.6.03", plistPath]
            try plutilTask.run()
            plutilTask.waitUntilExit()

            let xattrTask = Process()
            xattrTask.launchPath = "/usr/bin/xattr"
            xattrTask.arguments = ["-dr", "com.apple.quarantine", destinationAppURL.path]
            try xattrTask.run()
            xattrTask.waitUntilExit()

            let createInstallMediaPath = destinationAppURL.appendingPathComponent("Contents/Resources/createinstallmedia").path
            let codesignTask = Process()
            codesignTask.launchPath = "/usr/bin/codesign"
            codesignTask.arguments = ["-s", "-", "-f", createInstallMediaPath]
            try codesignTask.run()
            codesignTask.waitUntilExit()

            effectiveAppURL = destinationAppURL
        } else if sourceIsMountedVolume || isCatalina || needsCodesign {
            let destinationAppURL = tempWorkURL.appendingPathComponent(sourceAppURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationAppURL.path) {
                try fileManager.removeItem(at: destinationAppURL)
            }
            try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)

            if isCatalina || needsCodesign {
                try performLocalCodesign(on: destinationAppURL)
            }

            effectiveAppURL = destinationAppURL
        }

        return HelperWorkflowRequestPayload(
            workflowKind: .standard,
            systemName: systemName,
            sourcePath: effectiveAppURL.path,
            targetVolumePath: drive.url.path,
            targetBSDName: drive.device,
            targetLabel: drive.url.lastPathComponent,
            needsPreformat: shouldPreformat,
            isCatalina: isCatalina,
            requiresApplicationPathArg: isLegacySystem || isSierra,
            postInstallSourceAppPath: isCatalina ? sourceAppURL.resolvingSymlinksInPath().path : nil,
            requesterUID: requesterUID
        )
    }

    private func preflightTargetVolumeWriteAccess(_ volumeURL: URL) throws {
        guard volumeURL.path.hasPrefix("/Volumes/") else {
            return
        }

        let probeURL = volumeURL.appendingPathComponent(".macusb-write-probe-\(UUID().uuidString)")

        do {
            try Data("macUSB".utf8).write(to: probeURL, options: .atomic)
            try? FileManager.default.removeItem(at: probeURL)
        } catch {
            let nsError = error as NSError
            let underlyingCode = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            let code = underlyingCode ?? nsError.code
            if code == Int(EPERM) || code == Int(EACCES) {
                throw NSError(
                    domain: "macUSB",
                    code: code,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Brak uprawnien do zapisu na wybranym nosniku USB. Zezwol aplikacji macUSB na dostep do Woluminow wymiennych w Ustawieniach systemowych > Prywatnosc i ochrona, a nastepnie sprobuj ponownie."
                    ]
                )
            }
            throw error
        }
    }

    func cancelHelperWorkflowIfNeeded(completion: @escaping () -> Void) {
        guard let workflowID = activeHelperWorkflowID else {
            completion()
            return
        }

        log("Wysyłam żądanie anulowania helper workflow: \(workflowID)")

        PrivilegedOperationClient.shared.cancelWorkflow(workflowID) { _, _ in
            PrivilegedOperationClient.shared.clearHandlers(for: workflowID)
            activeHelperWorkflowID = nil
            isHelperWorking = false
            stopHelperWriteSpeedMonitoring()
            completion()
        }
    }

    private func startHelperWriteSpeedMonitoring(for drive: USBDrive) {
        stopHelperWriteSpeedMonitoring(resetText: false)
        helperWriteSpeedText = "Pomiar..."

        let wholeDisk = extractWholeDiskName(from: drive.device)

        helperWriteSpeedTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            sampleHelperWriteSpeed(for: wholeDisk)
        }

        sampleHelperWriteSpeed(for: wholeDisk)
    }

    func stopHelperWriteSpeedMonitoring(resetText: Bool = true) {
        helperWriteSpeedTimer?.invalidate()
        helperWriteSpeedTimer = nil
        helperWriteSpeedSampleInFlight = false
        if resetText {
            helperWriteSpeedText = "— MB/s"
        }
    }

    private func sampleHelperWriteSpeed(for wholeDisk: String) {
        guard isHelperWorking else { return }
        guard !helperWriteSpeedSampleInFlight else { return }
        helperWriteSpeedSampleInFlight = true

        DispatchQueue.global(qos: .utility).async {
            let measured = fetchWriteSpeedMBps(for: wholeDisk)
            DispatchQueue.main.async {
                helperWriteSpeedSampleInFlight = false
                guard isHelperWorking else { return }
                if let measured {
                    helperWriteSpeedText = String(format: "%.2f MB/s", measured)
                } else {
                    helperWriteSpeedText = "— MB/s"
                }
            }
        }
    }

    private func fetchWriteSpeedMBps(for wholeDisk: String) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/iostat")
        process.arguments = ["-Id", wholeDisk, "1", "2"]

        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        process.environment = env

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return nil
        }

        let lines = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0.range(of: #"\d"#, options: .regularExpression) != nil }
            .filter { !$0.contains("KB/t") && !$0.contains("xfrs") && !$0.lowercased().contains("disk") }

        guard let lastDataLine = lines.last else {
            return nil
        }

        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+(?:[.,][0-9]+)?"#) else {
            return nil
        }
        let nsRange = NSRange(lastDataLine.startIndex..<lastDataLine.endIndex, in: lastDataLine)
        let matches = regex.matches(in: lastDataLine, options: [], range: nsRange)
        guard let lastMatch = matches.last,
              let range = Range(lastMatch.range, in: lastDataLine) else {
            return nil
        }

        let rawValue = String(lastDataLine[range]).replacingOccurrences(of: ",", with: ".")
        guard let speed = Double(rawValue) else {
            return nil
        }

        return max(0, speed)
    }

    private func extractWholeDiskName(from device: String) -> String {
        if let range = device.range(of: #"^disk[0-9]+"#, options: .regularExpression) {
            return String(device[range])
        }
        return device
    }

}
