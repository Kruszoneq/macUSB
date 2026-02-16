import Foundation
import SwiftUI

extension UniversalInstallationView {
    func startCreationProcessEntry() {
        startCreationProcessWithHelper()
    }

    private func startCreationProcessWithHelper() {
        guard let drive = targetDrive else {
            navigateToCreationProgress = false
            errorMessage = String(localized: "Błąd: Nie wybrano dysku.")
            return
        }

        usbProcessStartedAt = Date()

        withAnimation(.easeInOut(duration: 0.4)) {
            isTabLocked = true
            isProcessing = true
        }

        processingTitle = String(localized: "Rozpoczynanie...")
        processingSubtitle = String(localized: "Przygotowywanie operacji...")
        isHelperWorking = false
        errorMessage = ""
        navigateToFinish = false
        didCancelCreation = false
        cancellationRequestedBeforeWorkflowStart = false
        helperOperationFailed = false
        stopUSBMonitoring()
        processingIcon = "lock.shield.fill"
        isCancelled = false
        helperProgressPercent = 0
        helperStageTitleKey = "Przygotowanie"
        helperStatusKey = "Sprawdzanie gotowości procesu..."
        helperCurrentStageKey = ""
        helperWriteSpeedText = "- MB/s"
        stopHelperWriteSpeedMonitoring()

        do {
            try preflightTargetVolumeWriteAccess(drive.url)
        } catch {
            if cancellationRequestedBeforeWorkflowStart {
                completeCancellationFlow()
                return
            }
            withAnimation {
                isProcessing = false
                isHelperWorking = false
                isTabLocked = false
                navigateToCreationProgress = false
                startUSBMonitoring()
                stopHelperWriteSpeedMonitoring()
                usbProcessStartedAt = nil
                errorMessage = error.localizedDescription
            }
            return
        }

        HelperServiceManager.shared.ensureReadyForPrivilegedWork { ready, failureReason in
            guard ready else {
                if cancellationRequestedBeforeWorkflowStart {
                    completeCancellationFlow()
                    return
                }
                withAnimation {
                    isProcessing = false
                    isHelperWorking = false
                    isTabLocked = false
                    navigateToCreationProgress = false
                    startUSBMonitoring()
                    stopHelperWriteSpeedMonitoring()
                    usbProcessStartedAt = nil
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
                            helperStageTitleKey = "Uruchamianie procesu"
                            helperStatusKey = "Nawiązywanie połączenia XPC..."
                        }

                        let failWorkflowStart: (String) -> Void = { message in
                            activeHelperWorkflowID = nil
                            if cancellationRequestedBeforeWorkflowStart {
                                completeCancellationFlow()
                                return
                            }
                            logError("Start helper workflow nieudany: \(message)", category: "Installation")
                            withAnimation {
                                isProcessing = false
                                isHelperWorking = false
                                isTabLocked = false
                                navigateToCreationProgress = false
                                startUSBMonitoring()
                                stopHelperWriteSpeedMonitoring()
                                usbProcessStartedAt = nil
                                errorMessage = message
                            }
                        }

                        var startHelperWorkflow: ((Bool) -> Void)!
                        startHelperWorkflow = { allowCompatibilityRecovery in
                            PrivilegedOperationClient.shared.startWorkflow(
                                request: request,
                                onEvent: { event in
                                    guard event.workflowID == activeHelperWorkflowID else { return }
                                    let previousStageKey = helperCurrentStageKey
                                    helperCurrentStageKey = event.stageKey
                                    helperProgressPercent = max(helperProgressPercent, min(event.percent, 100))
                                    if let localization = HelperWorkflowLocalizationKeys.presentation(for: event.stageKey) {
                                        helperStageTitleKey = localization.titleKey
                                        helperStatusKey = localization.statusKey
                                    } else {
                                        helperStageTitleKey = event.stageTitleKey
                                        helperStatusKey = event.statusKey
                                    }

                                    if isFormattingHelperStage(event.stageKey) {
                                        helperWriteSpeedText = "- MB/s"
                                    } else if isFormattingHelperStage(previousStageKey) {
                                        sampleHelperWriteSpeed(for: extractWholeDiskName(from: drive.device))
                                    }
                                },
                                onCompletion: { result in
                                    guard result.workflowID == activeHelperWorkflowID else { return }

                                    activeHelperWorkflowID = nil
                                    isHelperWorking = false
                                    stopHelperWriteSpeedMonitoring()

                                    if result.isUserCancelled || isCancelled {
                                        usbProcessStartedAt = nil
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
                                    guard allowCompatibilityRecovery, isLikelyHelperIPCContractMismatch(message) else {
                                        failWorkflowStart(message)
                                        return
                                    }

                                    log("Wykryto niezgodność kontraktu IPC helpera. Rozpoczynam automatyczne przeładowanie helpera.", category: "Installation")
                                    helperStageTitleKey = "Aktualizowanie helpera"
                                    helperStatusKey = "Wykryto starszą instancję helpera. Trwa ponowne uruchamianie usługi..."

                                    HelperServiceManager.shared.forceReloadForIPCContractMismatch { ready, recoveryMessage in
                                        guard ready else {
                                            failWorkflowStart(recoveryMessage ?? message)
                                            return
                                        }

                                        helperStageTitleKey = "Ponowne uruchamianie"
                                        helperStatusKey = "Helper został odświeżony. Ponawiamy start procesu..."
                                        startHelperWorkflow(false)
                                    }
                                },
                                onStarted: { workflowID in
                                    activeHelperWorkflowID = workflowID
                                    if cancellationRequestedBeforeWorkflowStart {
                                        cancelHelperWorkflowIfNeeded {
                                            completeCancellationFlow()
                                        }
                                        return
                                    }
                                    helperStageTitleKey = "Rozpoczynanie..."
                                    helperStatusKey = "Rozpoczynanie pierwszego etapu tworzenia nośnika..."
                                    helperCurrentStageKey = ""
                                    startHelperWriteSpeedMonitoring(for: drive)
                                    log("Uruchomiono helper workflow: \(workflowID)")
                                }
                            )
                        }

                        startHelperWorkflow(true)
                    }
                } catch {
                    DispatchQueue.main.async {
                        if cancellationRequestedBeforeWorkflowStart {
                            completeCancellationFlow()
                            return
                        }
                        withAnimation {
                            isProcessing = false
                            isHelperWorking = false
                            isTabLocked = false
                            navigateToCreationProgress = false
                            startUSBMonitoring()
                            stopHelperWriteSpeedMonitoring()
                            usbProcessStartedAt = nil
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

        let shouldPreformat = drive.needsFormatting && !isPPC

        if isRestoreLegacy {
            let sourceESD = sourceAppURL.appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")
            guard fileManager.fileExists(atPath: sourceESD.path) else {
                throw NSError(
                    domain: "macUSB",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono pliku InstallESD.dmg.")]
                )
            }

            return HelperWorkflowRequestPayload(
                workflowKind: .legacyRestore,
                systemName: systemName,
                sourceAppPath: sourceAppURL.path,
                originalImagePath: nil,
                tempWorkPath: tempWorkURL.path,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: shouldPreformat,
                isCatalina: false,
                isSierra: false,
                needsCodesign: false,
                requiresApplicationPathArg: false,
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

            return HelperWorkflowRequestPayload(
                workflowKind: .mavericks,
                systemName: systemName,
                sourceAppPath: sourceAppURL.path,
                originalImagePath: sourceImage.path,
                tempWorkPath: tempWorkURL.path,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: shouldPreformat,
                isCatalina: false,
                isSierra: false,
                needsCodesign: false,
                requiresApplicationPathArg: false,
                requesterUID: requesterUID
            )
        }

        if isPPC {
            return HelperWorkflowRequestPayload(
                workflowKind: .ppc,
                systemName: systemName,
                sourceAppPath: sourceAppURL.path,
                originalImagePath: originalImageURL?.path,
                tempWorkPath: tempWorkURL.path,
                targetVolumePath: drive.url.path,
                targetBSDName: drive.device,
                targetLabel: drive.url.lastPathComponent,
                needsPreformat: false,
                isCatalina: false,
                isSierra: false,
                needsCodesign: false,
                requiresApplicationPathArg: false,
                requesterUID: requesterUID
            )
        }

        return HelperWorkflowRequestPayload(
            workflowKind: .standard,
            systemName: systemName,
            sourceAppPath: sourceAppURL.path,
            originalImagePath: originalImageURL?.path,
            tempWorkPath: tempWorkURL.path,
            targetVolumePath: drive.url.path,
            targetBSDName: drive.device,
            targetLabel: drive.url.lastPathComponent,
            needsPreformat: shouldPreformat,
            isCatalina: isCatalina,
            isSierra: isSierra,
            needsCodesign: needsCodesign,
            requiresApplicationPathArg: isLegacySystem || isSierra,
            requesterUID: requesterUID
        )
    }

    private func isLikelyHelperIPCContractMismatch(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("nieprawidłowe żądanie helpera")
            || lowered.contains("nieprawidłowe zadanie helpera")
            || lowered.contains("couldn’t be read because it is missing")
            || lowered.contains("keynotfound")
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
            usbProcessStartedAt = nil
            completion()
        }
    }

    private func startHelperWriteSpeedMonitoring(for drive: USBDrive) {
        stopHelperWriteSpeedMonitoring(resetText: false)
        helperCurrentStageKey = ""
        helperWriteSpeedText = "- MB/s"

        let wholeDisk = extractWholeDiskName(from: drive.device)

        helperWriteSpeedTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            sampleHelperWriteSpeed(for: wholeDisk)
        }
    }

    func stopHelperWriteSpeedMonitoring(resetText: Bool = true) {
        helperWriteSpeedTimer?.invalidate()
        helperWriteSpeedTimer = nil
        helperWriteSpeedSampleInFlight = false
        helperCurrentStageKey = ""
        if resetText {
            helperWriteSpeedText = "- MB/s"
        }
    }

    private func sampleHelperWriteSpeed(for wholeDisk: String) {
        guard isHelperWorking else { return }
        guard !helperCurrentStageKey.isEmpty else { return }
        guard !isFormattingHelperStage(helperCurrentStageKey) else {
            helperWriteSpeedText = "- MB/s"
            return
        }
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
                    helperWriteSpeedText = "- MB/s"
                }
            }
        }
    }

    private func isFormattingHelperStage(_ stageKey: String) -> Bool {
        stageKey == "preformat" || stageKey == "ppc_format"
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
