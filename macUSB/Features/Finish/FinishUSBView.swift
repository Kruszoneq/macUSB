import SwiftUI
import AppKit
import UserNotifications

struct FinishUSBView: View {
    @ObservedObject private var menuState = MenuState.shared
    private let downloaderBlockReason = "usb_finish_summary"

    let systemName: String
    let mountPoint: URL
    let onReset: () -> Void
    let isPPC: Bool
    let isBetaInstaller: Bool
    let isLinuxWorkflow: Bool
    let isRawImageSelection: Bool
    let isWindowsWorkflow: Bool
    let loggingWorkflow: AppLogging.Workflow
    let didFail: Bool
    let didCancel: Bool
    let creationStartedAt: Date?
    let cleanupTempWorkURL: URL?
    let shouldDetachMountPoint: Bool
    let detectedSystemIcon: NSImage?
    let resultDetailMessage: String?
    let linuxErrorPresentation: LinuxWorkflowErrorPresentation?
    let targetWholeDiskBSDName: String?
    let isDebugEjectMode: Bool
    
    @State private var isCleaning: Bool = true
    @State private var cleanupSuccess: Bool = false
    @State private var cleanupErrorMessage: String? = nil
    @State private var didPlayResultSound: Bool = false
    @State private var didSendBackgroundNotification: Bool = false
    @State private var completionDurationText: String? = nil
    @StateObject private var ejectLogic: FinishUSBEjectLogic

    init(
        systemName: String,
        mountPoint: URL,
        onReset: @escaping () -> Void,
        isPPC: Bool,
        isBetaInstaller: Bool = false,
        isLinuxWorkflow: Bool = false,
        isRawImageSelection: Bool = false,
        isWindowsWorkflow: Bool = false,
        loggingWorkflow: AppLogging.Workflow,
        didFail: Bool,
        didCancel: Bool = false,
        creationStartedAt: Date? = nil,
        cleanupTempWorkURL: URL? = nil,
        shouldDetachMountPoint: Bool = true,
        detectedSystemIcon: NSImage? = nil,
        resultDetailMessage: String? = nil,
        linuxErrorPresentation: LinuxWorkflowErrorPresentation? = nil,
        targetWholeDiskBSDName: String? = nil,
        isDebugEjectMode: Bool = false
    ) {
        self.systemName = systemName
        self.mountPoint = mountPoint
        self.onReset = onReset
        self.isPPC = isPPC
        self.isBetaInstaller = isBetaInstaller
        self.isLinuxWorkflow = isLinuxWorkflow
        self.isRawImageSelection = isRawImageSelection
        self.isWindowsWorkflow = isWindowsWorkflow
        self.loggingWorkflow = loggingWorkflow
        self.didFail = didFail
        self.didCancel = didCancel
        self.creationStartedAt = creationStartedAt
        self.cleanupTempWorkURL = cleanupTempWorkURL
        self.shouldDetachMountPoint = shouldDetachMountPoint
        self.detectedSystemIcon = detectedSystemIcon
        self.resultDetailMessage = resultDetailMessage
        self.linuxErrorPresentation = linuxErrorPresentation
        self.targetWholeDiskBSDName = targetWholeDiskBSDName
        self.isDebugEjectMode = isDebugEjectMode
        _ejectLogic = StateObject(
            wrappedValue: FinishUSBEjectLogic(
                targetWholeDiskBSDName: targetWholeDiskBSDName,
                isDebugMode: isDebugEjectMode,
                loggingWorkflow: loggingWorkflow
            )
        )
    }
    
    private var isSnowLeopard: Bool {
        let lower = systemName.lowercased()
        return lower.contains("snow leopard") || lower.contains("10.6")
    }
    
    var tempWorkURL: URL {
        return cleanupTempWorkURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_temp")
    }

    private var isCancelledResult: Bool { didCancel }
    private var isFailedResult: Bool { didFail && !didCancel }
    private var isSuccessResult: Bool { !didFail && !didCancel }
    private var shouldShowEjectSection: Bool {
        guard isSuccessResult else { return false }
        if isDebugEjectMode { return true }
        return targetWholeDiskBSDName != nil
    }
    private func finishEjectText(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: "FinishUSB")
    }
    private var ejectActionButtonLabel: String {
        if ejectLogic.state == .debugDisabled {
            return "DEBUG"
        }
        if ejectLogic.state == .spotlightBlocked
            || ejectLogic.state == .forceInProgress
            || ejectLogic.state == .forceFailed {
            return finishEjectText("finish.eject.button.force")
        }
        if ejectLogic.state == .failed {
            return finishEjectText("finish.eject.error.retry")
        }
        return finishEjectText("finish.eject.button.action")
    }
    private var isEjectActionEnabled: Bool {
        switch ejectLogic.state {
        case .ready, .spotlightBlocked, .failed, .forceFailed:
            return true
        case .inProgress, .forceInProgress, .unavailable, .ejected, .debugDisabled:
            return false
        }
    }
    private var isEjectActionInProgress: Bool {
        ejectLogic.state == .inProgress || ejectLogic.state == .forceInProgress
    }
    private var sectionIconFont: Font { .title3 }
    @ViewBuilder
    private func hangingBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "•")
                .frame(width: 10, alignment: .leading)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var primaryResultTone: MacUSBSurfaceTone {
        if isCancelledResult { return .warning }
        if isFailedResult { return .error }
        return .success
    }
    private var primaryResultIconName: String {
        if isCancelledResult { return "exclamationmark.triangle.fill" }
        if isFailedResult { return "xmark.octagon.fill" }
        return "checkmark.circle.fill"
    }
    private var primaryResultColor: Color {
        if isCancelledResult { return .orange }
        if isFailedResult { return .red }
        return .green
    }
    private var primaryResultTitle: String {
        if isCancelledResult { return String(localized: "finish.result.cancelled.title", table: "FinishUSB") }
        if isFailedResult { return String(localized: "finish.result.failure.title", table: "FinishUSB") }
        return String(localized: "finish.result.success.title", table: "FinishUSB")
    }
    private var primaryResultSubtitle: String {
        if isCancelledResult { return String(localized: "finish.result.cancelled.description", table: "FinishUSB") }
        if isFailedResult { return String(localized: "finish.result.failure.description", table: "FinishUSB") }
        return String(localized: "finish.result.success.description", table: "FinishUSB")
    }
    private var summaryTitleText: String {
        if isCancelledResult { return String(localized: "finish.summary.cancelled.title", table: "FinishUSB") }
        if isRawImageSelection, isFailedResult { return String(localized: "finish.raw_image.result.failure.title", table: "FinishUSB") }
        if isRawImageSelection { return String(localized: "finish.raw_image.result.success.title", table: "FinishUSB") }
        if isFailedResult { return String(localized: "finish.summary.failure.title", table: "FinishUSB") }
        if isLinuxWorkflow { return String(localized: "finish.linux.summary.success.title", table: "FinishUSB") }
        return String(localized: "finish.summary.success.title", table: "FinishUSB")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
                    StatusCard(tone: primaryResultTone) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center) {
                                Image(systemName: primaryResultIconName)
                                    .font(sectionIconFont)
                                    .foregroundColor(primaryResultColor)
                                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(primaryResultTitle).font(.headline).foregroundColor(primaryResultColor)
                                    Text(primaryResultSubtitle).font(.caption).foregroundColor(primaryResultColor.opacity(0.9))
                                }
                                Spacer()
                            }

                            Divider()
                                .overlay(Color.secondary.opacity(0.18))

                            HStack(alignment: .center) {
                                if isRawImageSelection {
                                    Image(systemName: "opticaldisc.fill")
                                        .font(sectionIconFont)
                                        .foregroundColor(primaryResultColor)
                                        .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                } else if isSuccessResult, let detectedSystemIcon {
                                    if detectedSystemIcon.isTemplate {
                                        Image(nsImage: detectedSystemIcon)
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 32, height: 32)
                                            .foregroundColor(primaryResultColor)
                                    } else {
                                        Image(nsImage: detectedSystemIcon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 32, height: 32)
                                    }
                                } else {
                                    Image(systemName: "externaldrive.fill")
                                        .font(sectionIconFont)
                                        .foregroundColor(primaryResultColor)
                                        .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(summaryTitleText).font(.caption).foregroundColor(primaryResultColor.opacity(0.9))
                                    HStack(spacing: 8) {
                                        Text(verbatim: systemName)
                                            .font(.headline)
                                            .foregroundColor(primaryResultColor)
                                        if isBetaInstaller && !isRawImageSelection {
                                            MacOSBetaBadge(tint: primaryResultColor)
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }
                    }

                    if isFailedResult, isLinuxWorkflow, let linuxErrorPresentation {
                        StatusCard(tone: .warning, density: .compact) {
                            HStack(alignment: .top) {
                                Image(systemName: linuxErrorPresentation.iconSystemName)
                                    .font(sectionIconFont)
                                    .foregroundColor(.orange)
                                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(linuxErrorPresentation.titleKey), tableName: "FinishUSB")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Text(LocalizedStringKey(effectiveLinuxErrorDescriptionKey(linuxErrorPresentation)), tableName: "FinishUSB")
                                        .font(.subheadline)
                                        .foregroundColor(.orange.opacity(0.9))
                                }
                                Spacer()
                            }
                        }
                    } else if let resultDetailMessage, !resultDetailMessage.isEmpty {
                        StatusCard(tone: isCancelledResult ? .warning : .error, density: .compact) {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle.fill")
                                    .font(sectionIconFont)
                                    .foregroundColor(isCancelledResult ? .orange : .red)
                                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isCancelledResult ? String(localized: "finish.result.cancelled.details.title", table: "FinishUSB") : String(localized: "finish.result.failure.details.title", table: "FinishUSB"))
                                        .font(.headline)
                                        .foregroundColor(isCancelledResult ? .orange : .red)
                                    Text(resultDetailMessage)
                                        .font(.subheadline)
                                        .foregroundColor(isCancelledResult ? .orange.opacity(0.9) : .red.opacity(0.85))
                                }
                                Spacer()
                            }
                        }
                    }

                    if isSuccessResult && !isRawImageSelection {
                        StatusCard(tone: .neutral, density: .compact) {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("finish.nextsteps.title", tableName: "FinishUSB").font(.headline).foregroundColor(.primary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        if isLinuxWorkflow {
                                            Text("finish.linux.nextsteps.point1", tableName: "FinishUSB")
                                            Text("finish.linux.nextsteps.point2", tableName: "FinishUSB")
                                            Text("finish.linux.nextsteps.point3", tableName: "FinishUSB")
                                        } else if isWindowsWorkflow {
                                            hangingBullet(String(localized: "finish.nextsteps.windows.pc.point1", table: "FinishUSB"))
                                            hangingBullet(String(localized: "finish.nextsteps.windows.pc.point2", table: "FinishUSB"))
                                            hangingBullet(String(localized: "finish.nextsteps.windows.pc.point3", table: "FinishUSB"))
                                        } else {
                                            Text("finish.macos.nextsteps.point1", tableName: "FinishUSB")
                                            Text("finish.macos.nextsteps.point2", tableName: "FinishUSB")
                                            Text("finish.macos.nextsteps.point3", tableName: "FinishUSB")
                                        }
                                    }
                                    .font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    if shouldShowEjectSection {
                        finishEjectSection
                            .animation(.easeInOut(duration: 0.3), value: ejectLogic.state)
                    }

                    if isSuccessResult && isPPC && !isSnowLeopard {
                        StatusCard(tone: .subtle, density: .compact) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    Image(systemName: "globe.europe.africa.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("finish.macos.ppc.guidance.title", tableName: "FinishUSB").font(.headline).foregroundColor(.primary)
                                        Text("finish.macos.ppc.guidance.description", tableName: "FinishUSB")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        if let url = URL(string: "https://macusb.app/pages/guides/ppc_boot_instructions.html") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Text("finish.macos.ppc.guidance.action", tableName: "FinishUSB")
                                            Image(systemName: "arrow.up.right.square")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                    Spacer()
                                }
                                .padding(.top, 12)
                            }
                        }
                    }
                }
                .padding(.horizontal, MacUSBDesignTokens.contentHorizontalPadding)
                .padding(.vertical, MacUSBDesignTokens.contentVerticalPadding)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                if isCleaning {
                    StatusCard(tone: .active, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "trash.fill").font(sectionIconFont).foregroundColor(.accentColor).frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("finish.cleanup.progress.title", tableName: "FinishUSB")
                                    .font(.headline)
                                    .bold()
                                    .foregroundColor(.accentColor)
                                Text("finish.wait.description", tableName: "FinishUSB")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    VStack(spacing: MacUSBDesignTokens.bottomBarContentSpacing) {
                        if cleanupSuccess {
                            StatusCard(tone: .subtle, density: .compact) {
                                HStack(alignment: .center) {
                                    Image(systemName: "checkmark.circle.fill").font(sectionIconFont).foregroundColor(.green).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("finish.completion.title", tableName: "FinishUSB").font(.headline).foregroundColor(.green)
                                        if let completionDurationText {
                                            Text(completionDurationText)
                                                .font(.subheadline)
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                        } else {
                            StatusCard(tone: .error, density: .compact) {
                                HStack(alignment: .top) {
                                    Image(systemName: "xmark.octagon.fill").font(sectionIconFont).foregroundColor(.red).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("finish.cleanup.error.title", tableName: "FinishUSB").font(.headline).foregroundColor(.red)
                                        if let msg = cleanupErrorMessage {
                                            Text(msg).font(.caption).foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }

                        Button(action: { onReset() }) {
                            HStack {
                                Text("finish.action.restart", tableName: "FinishUSB")
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .macUSBSecondaryButtonStyle()

                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            HStack {
                                Text("finish.action.quit", tableName: "FinishUSB")
                                Image(systemName: "xmark.circle.fill")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .macUSBPrimaryButtonStyle()
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .frame(width: MacUSBDesignTokens.windowWidth, height: MacUSBDesignTokens.windowHeight)
        .navigationTitle(Text("finish.navigation.title", tableName: "FinishUSB"))
        .navigationBarBackButtonHidden(true)
        .background(
            WindowAccessor_Finish { window in
                window.styleMask.remove(.resizable)
            }
        )
        .onAppear {
            menuState.setDownloaderAccessBlocked(true, reason: downloaderBlockReason)
            ejectLogic.prepareForPresentation()
            ejectLogic.startAvailabilityMonitoring()
            playResultSoundOnce()
            performCleanupWithDelay()
            sendSystemNotificationIfInactive()
        }
        .onDisappear {
            menuState.setDownloaderAccessBlocked(false, reason: downloaderBlockReason)
            ejectLogic.stopAvailabilityMonitoring()
        }
    }

    private func effectiveLinuxErrorDescriptionKey(_ presentation: LinuxWorkflowErrorPresentation) -> String {
        if isRawImageSelection,
           presentation.descriptionKey == "finish.linux.error.verify_write.generic" {
            return "finish.raw_image.error.verify_write.generic"
        }
        return presentation.descriptionKey
    }

    @ViewBuilder
    private var finishEjectSection: some View {
        switch ejectLogic.state {
        case .ejected:
            StatusCard(tone: .success, density: .compact) {
                HStack(alignment: .center) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(sectionIconFont)
                        .foregroundColor(.green)
                        .frame(width: MacUSBDesignTokens.iconColumnWidth)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("finish.eject.success.title", tableName: "FinishUSB")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text("finish.eject.success.description", tableName: "FinishUSB")
                            .font(.subheadline)
                            .foregroundColor(.green.opacity(0.85))
                    }
                    Spacer()
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))

        default:
            VStack(spacing: MacUSBDesignTokens.sectionGroupSpacing) {
                if ejectLogic.state == .spotlightBlocked {
                    StatusCard(tone: .warning, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(sectionIconFont)
                                .foregroundColor(.orange)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("finish.eject.spotlight.warning.title", tableName: "FinishUSB")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text("finish.eject.spotlight.warning.description", tableName: "FinishUSB")
                                    .font(.subheadline)
                                    .foregroundColor(.orange.opacity(0.85))
                            }
                            Spacer()
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if ejectLogic.state == .failed || ejectLogic.state == .forceFailed {
                    StatusCard(tone: .error, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(sectionIconFont)
                                .foregroundColor(.red)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(LocalizedStringKey(
                                    ejectLogic.state == .forceFailed
                                    ? "finish.eject.force.error.title"
                                    : "finish.eject.error.title"
                                ), tableName: "FinishUSB")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text(LocalizedStringKey(
                                    ejectLogic.state == .forceFailed
                                    ? "finish.eject.force.error.description"
                                    : "finish.eject.error.description"
                                ), tableName: "FinishUSB")
                                    .font(.subheadline)
                                    .foregroundColor(.red.opacity(0.85))
                            }
                            Spacer()
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                StatusCard(tone: .active, density: .compact) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            Image(systemName: "eject.fill")
                                .font(sectionIconFont)
                                .foregroundColor(.accentColor)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(LocalizedStringKey(
                                    ejectLogic.state == .unavailable
                                    ? "finish.eject.unavailable.title"
                                    : "finish.eject.card.title"
                                ), tableName: "FinishUSB")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                                Text(LocalizedStringKey(
                                    ejectLogic.state == .unavailable
                                    ? "finish.eject.unavailable.description"
                                    : "finish.eject.card.description"
                                ), tableName: "FinishUSB")
                                .font(.subheadline)
                                .foregroundColor(.accentColor.opacity(0.9))
                            }
                            Spacer()
                        }

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                ejectLogic.performEject()
                            }
                        }) {
                            HStack {
                                Text(verbatim: ejectActionButtonLabel)
                                if isEjectActionInProgress {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "eject")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .macUSBPrimaryButtonStyle(isEnabled: isEjectActionEnabled)
                        .disabled(!isEjectActionEnabled)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    // --- LOGIKA ---
    func performCleanupWithDelay() {
        isCleaning = true
        AppLogging.info(
            "Finish cleanup requested: executor=app, detachMountPoint=\(shouldDetachMountPoint), mountPoint=\(mountPoint.path), temporaryPath=\(tempWorkURL.path).",
            stage: .usb,
            workflow: loggingWorkflow
        )
        let cleanupToken = AppActiveOperationRegistry.shared.begin(
            kind: .cleanup,
            context: "finish_screen_cleanup",
            logStage: .usb,
            logWorkflow: loggingWorkflow
        )
        DispatchQueue.global(qos: .userInitiated).async {
            var success = true
            var errorMsg: String? = nil
            if self.shouldDetachMountPoint {
                let unmountTask = Process()
                unmountTask.launchPath = "/usr/bin/hdiutil"
                unmountTask.arguments = ["detach", self.mountPoint.path, "-force"]
                try? unmountTask.run()
                unmountTask.waitUntilExit()
                let detachMessage = "Finish cleanup image detach completed: path=\(self.mountPoint.path), exitCode=\(unmountTask.terminationStatus)."
                if unmountTask.terminationStatus == 0 {
                    AppLogging.info(detachMessage, stage: .usb, workflow: self.loggingWorkflow)
                } else {
                    AppLogging.error(detachMessage, stage: .usb, workflow: self.loggingWorkflow)
                }
            }
            let tempCleanupNeeded = FileManager.default.fileExists(atPath: self.tempWorkURL.path)
            if tempCleanupNeeded {
                do {
                    try FileManager.default.removeItem(at: self.tempWorkURL)
                    AppLogging.info(
                        "Fallback cleanup removed temporary files: path=\(self.tempWorkURL.path).",
                        stage: .usb,
                        workflow: self.loggingWorkflow
                    )
                } catch {
                    let stillExists = FileManager.default.fileExists(atPath: self.tempWorkURL.path)
                    let nsError = error as NSError
                    let isNoSuchFile = nsError.domain == NSCocoaErrorDomain
                        && (nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError)

                    if !stillExists || isNoSuchFile {
                        AppLogging.info(
                            "Fallback cleanup skipped: temporary files were already removed.",
                            stage: .usb,
                            workflow: self.loggingWorkflow
                        )
                    } else {
                        success = false
                        AppLogging.error(
                            "Fallback cleanup failed: path=\(self.tempWorkURL.path), error=\(error.localizedDescription)",
                            stage: .usb,
                            workflow: self.loggingWorkflow
                        )
                        errorMsg = String(format: String(localized: "finish.cleanup.error.description", table: "FinishUSB"), error.localizedDescription)
                    }
                }
            } else {
                AppLogging.info(
                    "Fallback cleanup skipped: temporary files were already absent at path=\(self.tempWorkURL.path).",
                    stage: .usb,
                    workflow: self.loggingWorkflow
                )
            }
            
            DispatchQueue.main.async {
                let durationMetrics = self.currentCompletionDuration()
                let durationText = self.makeCompletionDurationText(durationMetrics)
                let resultState = self.didCancel ? "cancelled" : (self.didFail ? "failed" : "success")
                if let durationMetrics {
                    AppLogging.info(
                        "USB creation duration: \(durationMetrics.displayText) (\(durationMetrics.totalSeconds)s), result=\(resultState), cleanupSuccess=\(success).",
                        stage: .usb,
                        workflow: self.loggingWorkflow
                    )
                } else {
                    AppLogging.info(
                        "USB creation duration unavailable: start time missing, result=\(resultState), cleanupSuccess=\(success).",
                        stage: .usb,
                        workflow: self.loggingWorkflow
                    )
                }

                withAnimation(.easeInOut(duration: 0.5)) {
                    self.cleanupSuccess = success
                    self.cleanupErrorMessage = errorMsg
                    self.completionDurationText = durationText
                    self.isCleaning = false
                }
                cleanupToken.finish()
            }
        }
    }

    private func currentCompletionDuration() -> (totalSeconds: Int, displayText: String)? {
        guard let creationStartedAt else { return nil }

        let totalSeconds = max(0, Int(Date().timeIntervalSince(creationStartedAt)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let displayText = String(format: "%02dm %02ds", minutes, seconds)
        return (totalSeconds: totalSeconds, displayText: displayText)
    }

    private func makeCompletionDurationText(_ duration: (totalSeconds: Int, displayText: String)?) -> String? {
        guard !didFail && !didCancel else { return nil }
        guard let duration else { return nil }

        let minutes = duration.totalSeconds / 60
        let seconds = duration.totalSeconds % 60
        return String(
            format: String(localized: "finish.completion.duration", table: "FinishUSB"),
            minutes,
            seconds
        )
    }
    
    // --- DŹWIĘK WYNIKU ---
    func playResultSoundOnce() {
        // Zabezpieczenie przed wielokrotnym odtworzeniem
        if didPlayResultSound { return }
        didPlayResultSound = true

        if didCancel {
            return
        }
        
        if didFail {
            // Dźwięk niepowodzenia
            if let failSound = NSSound(named: NSSound.Name("Basso")) {
                failSound.play()
            }
        } else {
            // Preferowany dźwięk sukcesu.
            let bundledSoundURL =
                Bundle.main.url(forResource: "burn_complete", withExtension: "aif", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: "burn_complete", withExtension: "aif")

            if let bundledSoundURL,
               let successSound = NSSound(contentsOf: bundledSoundURL, byReference: false) {
                successSound.play()
            } else if let successSound = NSSound(named: NSSound.Name("burn_success")) {
                successSound.play()
            } else if let successSound = NSSound(named: NSSound.Name("Glass")) {
                // Fallback dla środowisk bez customowego dźwięku.
                successSound.play()
            } else if let hero = NSSound(named: NSSound.Name("Hero")) {
                hero.play()
            }
        }
    }

    // --- POWIADOMIENIE SYSTEMOWE ---
    func sendSystemNotificationIfInactive() {
        guard !didSendBackgroundNotification else { return }
        guard !NSApp.isActive else { return }
        guard !didCancel else { return }
        didSendBackgroundNotification = true

        let title: String
        let body: String
        if isRawImageSelection {
            title = isFailedResult
                ? String(localized: "finish.raw_image.result.failure.title", table: "FinishUSB")
                : String(localized: "finish.raw_image.result.success.title", table: "FinishUSB")
            body = isFailedResult
                ? String(localized: "finish.raw_image.notification.failure.description", table: "FinishUSB")
                : String(localized: "finish.raw_image.notification.success.description", table: "FinishUSB")
        } else {
            title = isFailedResult ? String(localized: "finish.notification.failure.title", table: "FinishUSB") : String(localized: "finish.notification.success.title", table: "FinishUSB")
            body = isFailedResult
                ? String(localized: "finish.notification.failure.description", table: "FinishUSB")
                : String(localized: "finish.notification.success.description", table: "FinishUSB")
        }

        NotificationPermissionManager.shared.shouldDeliverInAppNotification { shouldDeliver in
            guard shouldDeliver else { return }
            let center = UNUserNotificationCenter.current()
            scheduleSystemNotification(title: title, body: body, center: center)
        }
    }

    func scheduleSystemNotification(title: String, body: String, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "macUSB.finish.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
}

// Pomocnik dla FinishUSBView (aby uniknąć konfliktów nazw)
struct WindowAccessor_Finish: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { context.coordinator.callback(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(callback: callback) }
    class Coordinator {
        let callback: (NSWindow) -> Void
        init(callback: @escaping (NSWindow) -> Void) { self.callback = callback }
    }
}
