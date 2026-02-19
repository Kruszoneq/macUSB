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
        helperStatusKey = "Przygotowywanie operacji..."
        helperCurrentStageKey = ""
        helperWriteSpeedText = "- MB/s"
        helperCopyProgressPercent = 0
        helperCopiedBytes = 0
        helperTransferStageTotals = [:]
        helperTransferBaselineBytes = -1
        helperTransferStageForBaseline = ""
        helperTransferMonitorFailureCount = 0
        helperTransferMonitorFailureStageKey = ""
        helperTransferFallbackBytes = 0
        helperTransferFallbackStageKey = ""
        helperTransferFallbackLastSampleAt = nil
        helperTransferMonitoringRequestedBSDName = ""
        helperTransferMonitoringWholeDiskBSDName = ""
        helperTransferMonitoringTargetVolumePath = ""
        helperTransferMonitoringLastKnownPath = ""
        MenuState.shared.updateDebugCopiedData(bytes: 0)
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
                    let transferTotals = calculateTransferStageTotals(for: request)
                    DispatchQueue.main.async {
                        helperTransferMonitoringRequestedBSDName = request.targetBSDName
                        helperTransferMonitoringWholeDiskBSDName = extractWholeDiskName(from: request.targetBSDName)
                        helperTransferMonitoringTargetVolumePath = request.targetVolumePath
                        helperTransferMonitoringLastKnownPath = request.targetVolumePath

                        withAnimation {
                            isProcessing = false
                            isHelperWorking = true
                            helperProgressPercent = 0
                            helperStageTitleKey = "Uruchamianie procesu"
                            helperStatusKey = "Rozpoczynanie..."
                            helperTransferStageTotals = transferTotals
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
                                    let normalizedStageKey = canonicalStageKeyForPresentation(event.stageKey)
                                    let previousStageKey = helperCurrentStageKey
                                    helperCurrentStageKey = normalizedStageKey
                                    helperProgressPercent = max(helperProgressPercent, min(event.percent, 100))
                                    if let localization = HelperWorkflowLocalizationKeys.presentation(for: normalizedStageKey) {
                                        helperStageTitleKey = localization.titleKey
                                        helperStatusKey = localization.statusKey
                                    } else {
                                        helperStageTitleKey = event.stageTitleKey
                                        helperStatusKey = event.statusKey
                                    }

                                    handleTransferStageTransition(
                                        from: previousStageKey,
                                        to: normalizedStageKey,
                                        drive: drive
                                    )

                                    if isFormattingHelperStage(normalizedStageKey) {
                                        helperWriteSpeedText = "- MB/s"
                                    } else if isFormattingHelperStage(previousStageKey) {
                                        sampleHelperStageMetrics(for: drive)
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
                                    helperStageTitleKey = "Rozpoczynanie..."
                                    helperStatusKey = "Przygotowywanie operacji..."

                                    HelperServiceManager.shared.forceReloadForIPCContractMismatch { ready, recoveryMessage in
                                        guard ready else {
                                            failWorkflowStart(recoveryMessage ?? message)
                                            return
                                        }

                                        helperStageTitleKey = "Rozpoczynanie..."
                                        helperStatusKey = "Przygotowywanie operacji..."
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
                                    helperStatusKey = "Rozpoczynanie..."
                                    helperCurrentStageKey = ""
                                    helperCopyProgressPercent = 0
                                    helperCopiedBytes = 0
                                    helperTransferBaselineBytes = -1
                                    helperTransferStageForBaseline = ""
                                    helperTransferMonitorFailureCount = 0
                                    helperTransferMonitorFailureStageKey = ""
                                    helperTransferFallbackBytes = 0
                                    helperTransferFallbackStageKey = ""
                                    helperTransferFallbackLastSampleAt = nil
                                    helperTransferMonitoringRequestedBSDName = request.targetBSDName
                                    helperTransferMonitoringWholeDiskBSDName = extractWholeDiskName(from: request.targetBSDName)
                                    helperTransferMonitoringTargetVolumePath = request.targetVolumePath
                                    helperTransferMonitoringLastKnownPath = request.targetVolumePath
                                    MenuState.shared.updateDebugCopiedData(bytes: 0)
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
        let helperTargetBSDName = resolveHelperTargetBSDName(for: drive)

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
                targetBSDName: helperTargetBSDName,
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
                targetBSDName: helperTargetBSDName,
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
                targetBSDName: helperTargetBSDName,
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
            targetBSDName: helperTargetBSDName,
            targetLabel: drive.url.lastPathComponent,
            needsPreformat: shouldPreformat,
            isCatalina: isCatalina,
            isSierra: isSierra,
            needsCodesign: needsCodesign,
            requiresApplicationPathArg: isLegacySystem || isSierra,
            requesterUID: requesterUID
        )
    }

    private func resolveHelperTargetBSDName(for drive: USBDrive) -> String {
        if let resolved = USBDriveLogic.resolveFormattingWholeDiskBSDName(
            forVolumeURL: drive.url,
            fallbackBSDName: drive.device
        ) {
            return resolved
        }
        return extractWholeDiskName(from: drive.device)
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
                        NSLocalizedDescriptionKey: String(localized: "Brak uprawnień do zapisu na wybranym nośniku USB. Zresetuj uprawnienia aplikacji w menu Opcje → Resetuj uprawnienia dostępu do dysków zewnętrznych, a następnie spróbuj ponownie.")
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
        let preservedRequestedBSD = helperTransferMonitoringRequestedBSDName
        let preservedWholeDisk = helperTransferMonitoringWholeDiskBSDName
        let preservedTargetPath = helperTransferMonitoringTargetVolumePath
        let preservedLastKnownPath = helperTransferMonitoringLastKnownPath

        stopHelperWriteSpeedMonitoring(resetText: false)
        helperCurrentStageKey = ""
        helperWriteSpeedText = "- MB/s"
        helperCopyProgressPercent = 0
        helperCopiedBytes = 0
        helperTransferBaselineBytes = -1
        helperTransferStageForBaseline = ""
        helperTransferMonitorFailureCount = 0
        helperTransferMonitorFailureStageKey = ""
        helperTransferFallbackBytes = 0
        helperTransferFallbackStageKey = ""
        helperTransferFallbackLastSampleAt = nil
        helperTransferMonitoringRequestedBSDName = preservedRequestedBSD
        helperTransferMonitoringWholeDiskBSDName = preservedWholeDisk
        helperTransferMonitoringTargetVolumePath = preservedTargetPath
        helperTransferMonitoringLastKnownPath = preservedLastKnownPath
        MenuState.shared.updateDebugCopiedData(bytes: 0)

        helperWriteSpeedTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            sampleHelperStageMetrics(for: drive)
        }
    }

    func stopHelperWriteSpeedMonitoring(resetText: Bool = true) {
        helperWriteSpeedTimer?.invalidate()
        helperWriteSpeedTimer = nil
        helperWriteSpeedSampleInFlight = false
        helperCurrentStageKey = ""
        helperCopyProgressPercent = 0
        helperCopiedBytes = 0
        helperTransferBaselineBytes = -1
        helperTransferStageForBaseline = ""
        helperTransferMonitorFailureCount = 0
        helperTransferMonitorFailureStageKey = ""
        helperTransferFallbackBytes = 0
        helperTransferFallbackStageKey = ""
        helperTransferFallbackLastSampleAt = nil
        helperTransferMonitoringRequestedBSDName = ""
        helperTransferMonitoringWholeDiskBSDName = ""
        helperTransferMonitoringTargetVolumePath = ""
        helperTransferMonitoringLastKnownPath = ""
        MenuState.shared.updateDebugCopiedData(bytes: 0)
        if resetText {
            helperWriteSpeedText = "- MB/s"
        }
    }

    private func sampleHelperStageMetrics(for drive: USBDrive) {
        guard isHelperWorking else { return }
        guard !helperCurrentStageKey.isEmpty else { return }
        let monitoredWholeDisk = helperTransferMonitoringWholeDiskBSDName.isEmpty
            ? extractWholeDiskName(from: drive.device)
            : helperTransferMonitoringWholeDiskBSDName

        sampleHelperWriteSpeed(for: monitoredWholeDisk)
        sampleHelperTransferProgress(stageKey: helperCurrentStageKey)
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

    private func sampleHelperTransferProgress(stageKey: String) {
        guard isHelperWorking else { return }
        guard isTransferTrackedStage(stageKey) else {
            helperCopyProgressPercent = 0
            helperCopiedBytes = 0
            helperTransferMonitorFailureCount = 0
            helperTransferMonitorFailureStageKey = ""
            helperTransferFallbackBytes = 0
            helperTransferFallbackStageKey = ""
            helperTransferFallbackLastSampleAt = nil
            MenuState.shared.updateDebugCopiedData(bytes: 0)
            return
        }

        guard let totalBytes = helperTransferStageTotals[stageKey], totalBytes > 0 else {
            helperCopyProgressPercent = 0
            helperCopiedBytes = 0
            recordTransferMonitorFailure(
                stageKey: stageKey,
                reason: "brak rozmiaru danych źródłowych dla etapu transferu",
                totalBytes: nil
            )
            MenuState.shared.updateDebugCopiedData(bytes: 0)
            return
        }

        let measuredSpeed = currentMeasuredWriteSpeedMBps()

        guard measuredSpeed != nil else {
            recordTransferMonitorFailure(
                stageKey: stageKey,
                reason: "brak próbki prędkości zapisu (fallback speed-based)",
                totalBytes: totalBytes
            )
            advanceTransferUsingSpeedEstimate(
                stageKey: stageKey,
                totalBytes: totalBytes,
                measuredSpeedMBps: nil
            )
            return
        }

        recordTransferMonitorRecoveryIfNeeded(stageKey: stageKey)
        advanceTransferUsingSpeedEstimate(
            stageKey: stageKey,
            totalBytes: totalBytes,
            measuredSpeedMBps: measuredSpeed
        )
    }

    private func handleTransferStageTransition(from previousStage: String, to currentStage: String, drive: USBDrive) {
        guard previousStage != currentStage else { return }

        if isTransferTrackedStage(currentStage) {
            helperCopyProgressPercent = 0
            helperCopiedBytes = 0
            helperTransferMonitorFailureCount = 0
            helperTransferMonitorFailureStageKey = ""
            helperTransferFallbackBytes = 0
            helperTransferFallbackStageKey = currentStage
            helperTransferFallbackLastSampleAt = Date()
            let defaultWholeDisk = extractWholeDiskName(from: drive.device)
            let wholeDisk = resolveStageMonitoringWholeDisk(defaultWholeDisk: defaultWholeDisk) ?? defaultWholeDisk
            helperTransferBaselineBytes = -1
            helperTransferStageForBaseline = currentStage
            helperTransferMonitoringWholeDiskBSDName = wholeDisk
            MenuState.shared.updateDebugCopiedData(bytes: 0)
            sampleHelperTransferProgress(stageKey: currentStage)
            return
        }

        if isTransferTrackedStage(previousStage) {
            helperCopyProgressPercent = 0
            helperCopiedBytes = 0
            helperTransferBaselineBytes = -1
            helperTransferStageForBaseline = ""
            helperTransferMonitorFailureCount = 0
            helperTransferMonitorFailureStageKey = ""
            helperTransferFallbackBytes = 0
            helperTransferFallbackStageKey = ""
            helperTransferFallbackLastSampleAt = nil
            helperTransferMonitoringLastKnownPath = helperTransferMonitoringTargetVolumePath
            MenuState.shared.updateDebugCopiedData(bytes: 0)
        }
    }

    private func resolveStageMonitoringWholeDisk(defaultWholeDisk: String) -> String? {
        if !helperTransferMonitoringWholeDiskBSDName.isEmpty {
            return helperTransferMonitoringWholeDiskBSDName
        }

        if !helperTransferMonitoringRequestedBSDName.isEmpty {
            return extractWholeDiskName(from: helperTransferMonitoringRequestedBSDName)
        }

        return defaultWholeDisk
    }

    private func isFormattingHelperStage(_ stageKey: String) -> Bool {
        stageKey == "preformat" || stageKey == "ppc_format"
    }

    private func isTransferTrackedStage(_ stageKey: String) -> Bool {
        switch stageKey {
        case "restore", "ppc_restore", "createinstallmedia", "catalina_copy":
            return true
        default:
            return false
        }
    }

    private func calculateTransferStageTotals(for request: HelperWorkflowRequestPayload) -> [String: Int64] {
        var totals: [String: Int64] = [:]

        switch request.workflowKind {
        case .legacyRestore:
            let restorePath = URL(fileURLWithPath: request.sourceAppPath)
                .appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")
                .path
            if let bytes = sizeInBytes(at: restorePath) {
                totals["restore"] = bytes
            }

        case .mavericks:
            let restorePath = request.originalImagePath ?? request.sourceAppPath
            if let bytes = sizeInBytes(at: restorePath) {
                totals["restore"] = bytes
            }

        case .ppc:
            let ppcSourceCandidates = [request.originalImagePath, request.sourceAppPath]
                .compactMap { $0 }

            for candidatePath in ppcSourceCandidates {
                guard !candidatePath.hasPrefix("/Volumes/") else { continue }
                if let bytes = sizeInBytes(at: candidatePath) {
                    totals["ppc_restore"] = bytes
                    break
                }
            }

        case .standard:
            if let appBytes = sizeInBytes(at: request.sourceAppPath) {
                totals["createinstallmedia"] = appBytes
                if request.isCatalina {
                    totals["catalina_copy"] = appBytes
                }
            }
        }

        return totals
    }

    private func sizeInBytes(at path: String) -> Int64? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return directorySizeInBytes(at: path)
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
    }

    private func directorySizeInBytes(at path: String) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]

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

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8),
              let firstLine = output.split(separator: "\n").first,
              let firstToken = firstLine.split(separator: "\t").first,
              let kilobytes = Int64(String(firstToken)) else {
            return nil
        }

        return kilobytes * 1024
    }

    private func currentMeasuredWriteSpeedMBps() -> Double? {
        let normalized = helperWriteSpeedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let rawValue = normalized.split(separator: " ").first.map(String.init) ?? ""

        guard let measured = Double(rawValue), measured.isFinite, measured > 0 else {
            return nil
        }
        return measured
    }

    private func advanceTransferUsingSpeedEstimate(
        stageKey: String,
        totalBytes: Int64,
        measuredSpeedMBps: Double?
    ) {
        guard totalBytes > 0 else { return }
        let now = Date()

        if helperTransferFallbackStageKey != stageKey {
            helperTransferFallbackStageKey = stageKey
            helperTransferFallbackBytes = helperCopiedBytes
            helperTransferFallbackLastSampleAt = now
        }

        let previousSampleAt = helperTransferFallbackLastSampleAt ?? now.addingTimeInterval(-2)
        helperTransferFallbackLastSampleAt = now

        if let measuredSpeedMBps {
            let elapsedSeconds = max(0, now.timeIntervalSince(previousSampleAt))
            let bytesIncrement = Int64(measuredSpeedMBps * elapsedSeconds * 1_048_576)
            if bytesIncrement > 0 {
                helperTransferFallbackBytes = min(totalBytes, helperTransferFallbackBytes + bytesIncrement)
            }
        }

        helperCopiedBytes = max(helperCopiedBytes, helperTransferFallbackBytes)
        let calculatedPercent = (Double(helperCopiedBytes) / Double(totalBytes)) * 100.0
        helperCopyProgressPercent = max(helperCopyProgressPercent, min(max(calculatedPercent, 0), 99))
        MenuState.shared.updateDebugCopiedData(bytes: helperCopiedBytes)
    }

    private func recordTransferMonitorFailure(
        stageKey: String,
        reason: String,
        totalBytes: Int64?
    ) {
        if helperTransferMonitorFailureStageKey != stageKey {
            helperTransferMonitorFailureStageKey = stageKey
            helperTransferMonitorFailureCount = 0
        }

        helperTransferMonitorFailureCount += 1
        let failureCount = helperTransferMonitorFailureCount
        guard failureCount == 3 || failureCount % 10 == 0 else {
            return
        }

        let speedSnapshot = currentMeasuredWriteSpeedMBps()
            .map { String(format: "%.2f", $0) }
            ?? "n/a"
        let stagePercentSnapshot = String(format: "%.2f", helperProgressPercent)
        let totalBytesSnapshot = totalBytes.map(String.init) ?? "n/a"
        let copiedBytesSnapshot = String(helperCopiedBytes)

        AppLogging.info(
            "Transfer monitor fallback (\(reason)); stage=\(stageKey), requestedBSD=\(helperTransferMonitoringRequestedBSDName), targetPath=\(helperTransferMonitoringTargetVolumePath), failures=\(failureCount), speedSnapshotMBps=\(speedSnapshot), stagePercentSnapshot=\(stagePercentSnapshot), copiedBytes=\(copiedBytesSnapshot), totalBytes=\(totalBytesSnapshot)",
            category: "HelperLiveLog"
        )
    }

    private func recordTransferMonitorRecoveryIfNeeded(stageKey: String) {
        guard helperTransferMonitorFailureStageKey == stageKey else {
            helperTransferMonitorFailureCount = 0
            helperTransferMonitorFailureStageKey = ""
            return
        }

        let previousFailures = helperTransferMonitorFailureCount
        guard previousFailures >= 3 else {
            helperTransferMonitorFailureCount = 0
            helperTransferMonitorFailureStageKey = ""
            return
        }

        AppLogging.info(
            "Transfer monitor recovery; stage=\(stageKey), requestedBSD=\(helperTransferMonitoringRequestedBSDName), targetPath=\(helperTransferMonitoringTargetVolumePath), previousFailures=\(previousFailures)",
            category: "HelperLiveLog"
        )

        helperTransferMonitorFailureCount = 0
        helperTransferMonitorFailureStageKey = ""
    }

    private func canonicalStageKeyForPresentation(_ stageKey: String) -> String {
        switch stageKey {
        case "ditto", "catalina_ditto":
            return "catalina_copy"
        case "catalina_finalize":
            return "catalina_cleanup"
        case "asr_imagescan":
            return "imagescan"
        case "asr_restore":
            return "restore"
        default:
            return stageKey
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
