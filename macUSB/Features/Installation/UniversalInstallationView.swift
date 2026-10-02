import SwiftUI
import AppKit

struct UniversalInstallationView: View {
    @ObservedObject private var menuState = MenuState.shared
    private let downloaderBlockReason = "usb_installation_summary"

    let sourceAppURL: URL
    let targetDrive: USBDrive?
    let targetDriveDisplayName: String?
    let systemName: String
    let detectedSystemIcon: NSImage?
    let isBetaInstaller: Bool
    let originalImageURL: URL?
    let linuxFlowContext: LinuxInstallationFlowContext?
    let isWindowsWorkflow: Bool
    let windowsMountedSourcePath: String?
    let windowsAutounattendMacLocale: CreatorWindowsAutounattendMacLocale?
    let windowsArchitecture: WindowsArchitecture?
    let windowsFamily: WindowsFamily?
    let windowsBootCapabilities: WindowsBootCapabilities?
    let windowsWillSplitWim: Bool
    let macOSRosettaRequirement: MacOSRosettaRequirement
    
    // Flagi
    let needsCodesign: Bool
    let isLegacySystem: Bool // Yosemite/El Capitan
    let isRestoreLegacy: Bool // Lion/Mountain Lion
    // Flaga Catalina
    let isCatalina: Bool
    let isSierra: Bool
    let isMavericks: Bool
    let isPPC: Bool
    
    @Binding var rootIsActive: Bool
    @Binding var isTabLocked: Bool
    
    @State var isProcessing: Bool = false
    @State var processingTitle: String = ""
    @State var processingSubtitle: String = ""
    @State var processingIcon: String = "doc.on.doc.fill"

    @State var errorMessage: String = ""
    @State var isHelperWorking: Bool = false
    @State var helperProgressPercent: Double = 0
    @State var helperStageTitleKey: String = ""
    @State var helperStatusKey: String = ""
    @State var helperCurrentStageKey: String = ""
    @State var helperWriteSpeedText: String = "- MB/s"
    @State var helperCopyProgressPercent: Double = 0
    @State var helperCopiedBytes: Int64 = 0
    @State var helperTransferStageTotals: [String: Int64] = [:]
    @State var helperTransferBaselineBytes: Int64 = -1
    @State var helperTransferStageForBaseline: String = ""
    @State var helperTransferMonitorFailureCount: Int = 0
    @State var helperTransferMonitorFailureStageKey: String = ""
    @State var helperTransferFallbackBytes: Int64 = 0
    @State var helperTransferFallbackStageKey: String = ""
    @State var helperTransferFallbackLastSampleAt: Date?
    @State var helperTransferMonitoringRequestedBSDName: String = ""
    @State var helperTransferMonitoringWholeDiskBSDName: String = ""
    @State var helperTransferMonitoringTargetVolumePath: String = ""
    @State var helperTransferMonitoringLastKnownPath: String = ""
    @State var helperWriteSpeedTimer: Timer?
    @State var helperWriteSpeedSampleInFlight: Bool = false
    @State var activeHelperWorkflowID: String? = nil
    @State var navigateToCreationProgress: Bool = false
    @State var navigateToFinish: Bool = false
    @State var didCancelCreation: Bool = false
    @State var cancellationRequestedBeforeWorkflowStart: Bool = false
    @State var isCancelled: Bool = false
    @State var isUSBDisconnectedLock: Bool = false
    @State var usbCheckTimer: Timer?

    @State var helperOperationFailed: Bool = false
    @State var workflowResultDetailMessage: String? = nil
    @State var workflowResultErrorPresentation: LinuxWorkflowErrorPresentation? = nil
    @State var windowsPrerequisiteToolchainPresence: WindowsToolchainPresence? = WindowsToolchainProbeService.shared.detectPresence()
    @State var windowsPrerequisiteProbeInProgress: Bool = false
    @State var windowsAutounattendConfiguration: CreatorWindowsAutounattendConfiguration = CreatorWindowsAutounattendConfiguration()
    @State var windowsAutounattendOptionsPresented: Bool = false
    @State var selectedWindowsBootMode: WindowsBootMode? = nil
    @State var lastLoggedWindowsBootMode: WindowsBootMode? = nil
    @State var windowsMacUSBootPreflightInProgress: Bool = false
    @State var macOSRosettaState: CreatorMacOSRosettaState? = nil
    @State var macOSRosettaRetryGeneration: UUID? = nil
    @State var macOSRosettaSuccessVisible: Bool = false
    @State var macOSRosettaSuccessDismissalGeneration: UUID? = nil
    @State var macOSRosettaOperationToken: AppActiveOperationToken?
    
    @State var isCancelling: Bool = false
    @State var usbProcessStartedAt: Date?
    @State var usbCreationOperationToken: AppActiveOperationToken?
    @State var workflowCleanupOperationToken: AppActiveOperationToken?
    @State var usbProcessSleepBlockToken: UUID? = nil
    
    @State var hostingWindow: NSWindow?
    
    var tempWorkURL: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_temp")
    }
    private var targetWholeDiskBSDNameForFinish: String? {
        guard let targetDrive else { return nil }
        return USBDriveLogic.wholeDiskName(from: targetDrive.device)
    }

    private var showsIdleActions: Bool {
        !isProcessing && !isHelperWorking && !isCancelled && !isUSBDisconnectedLock && !isCancelling
    }
    private var isRawImageWorkflow: Bool {
        linuxFlowContext?.isRawImageSelection == true
    }
    private var selectedDriveSummaryName: String? {
        if let drive = targetDrive, drive.isWholeDiskTarget {
            let speedText = drive.usbSpeed?.rawValue ?? "USB"
            return "\(drive.device) - \(drive.size) - \(speedText)"
        }
        return targetDriveDisplayName ?? targetDrive?.displayName
    }
    private var missingFullDiskAccess: Bool { !menuState.hasFullDiskAccess }
    private var missingHelperBackgroundApproval: Bool { menuState.helperRequiresBackgroundApproval }
    private var shouldShowRequiredPermissionsWarning: Bool {
        missingFullDiskAccess || missingHelperBackgroundApproval
    }
    private var requiredPermissionsWarningMessage: String {
        switch (missingFullDiskAccess, missingHelperBackgroundApproval) {
        case (true, true):
            return String(localized: "creator.permissions.warning.both", table: "Creator")
        case (true, false):
            return String(localized: "creator.permissions.warning.full_disk_access", table: "Creator")
        case (false, true):
            return String(localized: "creator.permissions.warning.background", table: "Creator")
        case (false, false):
            return ""
        }
    }
    private var sectionIconFont: Font { .title3 }
    private var windowsAutounattendVersion: CreatorWindowsAutounattendWindowsVersion? {
        guard isWindowsWorkflow else { return nil }
        return CreatorWindowsAutounattendWindowsVersion.detected(
            from: systemName,
            architecture: windowsArchitecture
        )
    }
    private var windowsAutounattendShouldBlockStart: Bool {
        guard isWindowsWorkflow, windowsAutounattendConfiguration.hasSelectedOption else { return false }
        return !windowsAutounattendConfiguration.canStartWorkflow
    }
    private var shouldShowProcessDurationCard: Bool {
        guard windowsAutounattendVersion != nil,
              let windowsBootModeCardStyle else {
            return true
        }

        if case .configurable = windowsBootModeCardStyle {
            return false
        }
        return true
    }
    private var shouldBlockStartAction: Bool {
        windowsPrerequisiteShouldBlockStart
            || windowsAutounattendShouldBlockStart
            || windowsMacUSBootPreflightInProgress
            || macOSRosettaShouldBlockStart
    }
    private var processSectionDivider: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
            if windowsPrerequisiteShouldBlockStart {
                Text(String(localized: "creator.windows.summary.wimlib.divider.warning", table: "Creator"))
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.semibold)
            } else {
                Text(LocalizedStringKey(isRawImageWorkflow ? "creator.raw_image.summary.title" : "creator.summary.title"), tableName: "Creator")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
                    StatusCard(
                        tone: .neutral,
                        cornerRadius: MacUSBDesignTokens.prominentPanelCornerRadius(for: currentVisualMode())
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                if isRawImageWorkflow {
                                    Image(systemName: "opticaldisc.fill")
                                        .font(sectionIconFont)
                                        .foregroundColor(.secondary)
                                        .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                } else if let detectedSystemIcon {
                                    Image(nsImage: detectedSystemIcon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image(systemName: "applelogo")
                                        .font(sectionIconFont)
                                        .foregroundColor(.accentColor)
                                        .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(LocalizedStringKey(isRawImageWorkflow ? "creator.raw_image.selected_image.label" : "creator.summary.selected_system.label"), tableName: "Creator").font(.caption).foregroundColor(.secondary)
                                    HStack(spacing: 8) {
                                        Text(systemName).font(.headline).foregroundColor(.primary).bold()
                                        if isBetaInstaller && !isRawImageWorkflow {
                                            MacOSBetaBadge(tint: .secondary)
                                        }
                                    }
                                }
                                Spacer()
                            }

                            if let name = selectedDriveSummaryName {
                                Divider()
                                    .overlay(Color.secondary.opacity(0.18))

                                HStack {
                                    Image(systemName: "externaldrive.fill")
                                        .font(sectionIconFont)
                                        .foregroundColor(.secondary)
                                        .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(LocalizedStringKey("creator.summary.selected_drive.label"), tableName: "Creator").font(.caption).foregroundColor(.secondary)
                                        Text(name).font(.headline)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    if macOSRosettaShouldShowCard {
                        CreatorMacOSRosettaCardView(
                            state: effectiveMacOSRosettaState,
                            action: performMacOSRosettaPrimaryAction
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if isLinuxWorkflow {
                        StatusCard(tone: .active, density: .compact) {
                            HStack(alignment: .center) {
                                Image(systemName: "info.circle.fill")
                                    .font(sectionIconFont)
                                    .foregroundColor(.accentColor)
                                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(isRawImageWorkflow ? "creator.raw_image.summary.unreadable.title" : "creator.linux.summary.unreadable.title"), tableName: "Creator")
                                        .font(.headline)
                                        .foregroundColor(.accentColor)
                                    Text(LocalizedStringKey(isRawImageWorkflow
                                         ? "creator.raw_image.summary.unreadable.description"
                                         : "creator.linux.summary.unreadable.description"), tableName: "Creator")
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                }
                                Spacer()
                            }
                        }
                        .transition(.opacity)
                    }

                    if !windowsPrerequisiteShouldBlockStart,
                       let windowsBootModeCardStyle {
                        CreatorWindowsBootModeCardView(
                            style: windowsBootModeCardStyle,
                            eligibleModes: windowsBootCapabilities?.eligibleModes ?? [],
                            selectedMode: $selectedWindowsBootMode
                        )
                        .transition(.opacity)
                    }

                    if !windowsPrerequisiteShouldBlockStart,
                       let windowsAutounattendVersion {
                        CreatorWindowsAutounattendCardView(
                            windowsVersion: windowsAutounattendVersion,
                            configuration: $windowsAutounattendConfiguration,
                            isOptionsPresented: $windowsAutounattendOptionsPresented,
                            onConfigurationChanged: { _ in
                                persistWindowsAutounattendConfiguration()
                            }
                        )
                    }

                    if shouldShowRequiredPermissionsWarning {
                        StatusCard(tone: .warning, density: .compact) {
                            HStack(alignment: .center) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(sectionIconFont)
                                    .foregroundColor(.orange)
                                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey("creator.permissions.warning.title"), tableName: "Creator")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Text(requiredPermissionsWarningMessage)
                                        .font(.subheadline)
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                                Spacer()
                            }
                        }
                        .transition(.opacity)
                    }

                    if let drive = targetDrive, drive.usbSpeed == .usb2 {
                        StatusCard(tone: .warning, density: .compact) {
                            HStack(alignment: .center) {
                                Image(systemName: "externaldrive.fill")
                                    .font(sectionIconFont)
                                    .foregroundColor(.orange)
                                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey("creator.summary.usb_legacy.title"), tableName: "Creator")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Text(LocalizedStringKey(isRawImageWorkflow
                                         ? "creator.raw_image.summary.usb_legacy.description"
                                         : "creator.summary.usb_legacy.description"), tableName: "Creator")
                                        .font(.subheadline)
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                                Spacer()
                            }
                        }
                        .transition(.opacity)
                    }

                    processSectionDivider

                    if windowsPrerequisiteShouldBlockStart {
                        CreatorWindowsPrerequisiteCardView(
                            hasHomebrew: windowsPrerequisiteHasHomebrew,
                            isRefreshing: windowsPrerequisiteProbeInProgress,
                            onOpenHomebrewWebsite: openHomebrewWebsite,
                            onRefreshProbe: refreshWindowsPrerequisiteToolchainPresence
                        )
                    } else {
                        StatusCard(tone: .neutral, density: .compact) {
                            HStack(alignment: .top) {
                                Image(systemName: "gearshape.2").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(LocalizedStringKey("creator.summary.process.title"), tableName: "Creator").font(.headline)
                                    VStack(alignment: .leading, spacing: 4) {
                                        if isRawImageWorkflow {
                                            Text(LocalizedStringKey("creator.raw_image.summary.process.prepare"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.summary.process.unmount"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.raw_image.summary.process.copy"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.raw_image.summary.process.verify"), tableName: "Creator")
                                        } else if isLinuxWorkflow {
                                            Text(LocalizedStringKey("creator.linux.summary.process.prepare"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.summary.process.unmount"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.linux.summary.process.copy"), tableName: "Creator")
                                        } else if isWindowsWorkflow {
                                            Text(LocalizedStringKey("creator.windows.summary.process.prepare_source"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.windows.summary.process.prepare_target"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.windows.summary.process.create_and_verify"), tableName: "Creator")
                                            if resolvedWindowsBootMode == .bios {
                                                Text(LocalizedStringKey("creator.windows.summary.macusboot"), tableName: "Creator")
                                            }
                                        } else if isRestoreLegacy {
                                            Text(LocalizedStringKey("creator.macos.summary.process.verify"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.macos.summary.process.format"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.macos.summary.process.restore"), tableName: "Creator")
                                        } else if isPPC {
                                            Text(LocalizedStringKey("creator.macos.ppc.summary.process.format"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.macos.ppc.summary.process.restore"), tableName: "Creator")
                                        } else {
                                            Text(LocalizedStringKey("creator.macos.summary.process.prepare"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.macos.summary.process.format"), tableName: "Creator")
                                            Text(LocalizedStringKey("creator.macos.summary.process.copy"), tableName: "Creator")
                                            if isCatalina {
                                                Text(LocalizedStringKey("creator.macos.catalina.summary.process.finalize"), tableName: "Creator")
                                            }
                                        }
                                        if !isRawImageWorkflow {
                                            Text(LocalizedStringKey("creator.summary.process.cleanup_temp"), tableName: "Creator")
                                        }
                                    }
                                    .font(.subheadline).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }

                        if shouldShowProcessDurationCard {
                            StatusCard(tone: .neutral, density: .compact) {
                                HStack(alignment: .center, spacing: 15) {
                                    Image(systemName: "clock").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                    Text(LocalizedStringKey("creator.summary.duration.description"), tableName: "Creator").font(.subheadline).foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                    }

                    if !errorMessage.isEmpty {
                        StatusCard(tone: .error) {
                            HStack(alignment: .center) {
                                Image(systemName: "xmark.octagon.fill")
                                    .font(sectionIconFont)
                                    .foregroundColor(.red)
                                    .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey("creator.error.card.title"), tableName: "Creator")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                    Text(errorMessage)
                                        .font(.subheadline)
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                Spacer()
                            }
                        }
                        .transition(.scale)
                    }
                }
                .padding(.horizontal, MacUSBDesignTokens.contentHorizontalPadding)
                .padding(.vertical, MacUSBDesignTokens.contentVerticalPadding)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                if showsIdleActions {
                    VStack(spacing: MacUSBDesignTokens.bottomBarContentSpacing) {
                        Button(action: showStartCreationAlert) {
                            HStack {
                                Text(LocalizedStringKey("creator.action.start"), tableName: "Creator")
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .macUSBPrimaryButtonStyle(isEnabled: !shouldBlockStartAction)
                        .disabled(shouldBlockStartAction)

                        Button(action: returnToAnalysisViewPreservingSelection) {
                            HStack {
                                Text(LocalizedStringKey("creator.action.back"), tableName: "Creator")
                                Image(systemName: "arrow.left.circle")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .macUSBSecondaryButtonStyle()
                        .disabled(macOSRosettaIsBusy)
                    }
                    .transition(.opacity)
                }

                if isCancelling {
                    StatusCard(tone: .warning, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(sectionIconFont)
                                .foregroundColor(.orange)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey("creator.cancelling.card.title"), tableName: "Creator")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text(LocalizedStringKey("creator.wait.description"), tableName: "Creator")
                                    .font(.caption)
                                    .foregroundColor(.orange.opacity(0.8))
                            }
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                    .transition(.opacity)
                }

                if isCancelled {
                    StatusCard(tone: .warning, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(sectionIconFont)
                                .foregroundColor(.orange)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey("creator.cancelled.card.title"), tableName: "Creator")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text(LocalizedStringKey("creator.cancelled.card.description"), tableName: "Creator")
                                    .font(.caption)
                                    .foregroundColor(.orange.opacity(0.8))
                            }
                            Spacer()
                        }
                    }
                    .transition(.opacity)

                    Button(action: {
                        NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                        self.isTabLocked = false
                        self.rootIsActive = false
                    }) {
                        HStack {
                            Text(LocalizedStringKey("creator.action.restart"), tableName: "Creator")
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }
                    .macUSBSecondaryButtonStyle()
                }

                if isUSBDisconnectedLock {
                    StatusCard(tone: .error, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(sectionIconFont)
                                .foregroundColor(.red)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey("creator.disconnected.title"), tableName: "Creator")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text(LocalizedStringKey("creator.disconnected.card.description"), tableName: "Creator")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            Spacer()
                        }
                    }
                    .transition(.opacity)

                    Button(action: {
                        NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                        self.isTabLocked = false
                        self.rootIsActive = false
                    }) {
                        HStack {
                            Text(LocalizedStringKey("creator.action.restart"), tableName: "Creator")
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }
                    .macUSBSecondaryButtonStyle()
                }
            }
        }
        .frame(width: MacUSBDesignTokens.windowWidth, height: MacUSBDesignTokens.windowHeight)
        .navigationTitle(Text(LocalizedStringKey("creator.summary.navigation.title"), tableName: "Creator"))
        .navigationBarBackButtonHidden(isTabLocked)
        .background(
            WindowAccessor_Universal { window in
                self.hostingWindow = window
                window.styleMask.remove(NSWindow.StyleMask.resizable)
                
                AppWindowCloseGuard.shared.install(on: window)
                AppWindowCloseGuard.shared.setBeforeAllowedClose(nil)
            }
        )
        .background(
            NavigationLink(
                destination: CreationProgressView(
                    systemName: systemName,
                    mountPoint: effectiveMountPointForCreation,
                    detectedSystemIcon: detectedSystemIcon,
                    isBetaInstaller: isBetaInstaller,
                    isCatalina: isCatalina,
                    isRestoreLegacy: isRestoreLegacy,
                    isMavericks: isMavericks,
                    isPPC: isPPC,
                    isLinuxWorkflow: isLinuxWorkflow,
                    isRawImageSelection: isRawImageWorkflow,
                    isWindowsWorkflow: isWindowsWorkflow,
                    loggingWorkflow: creationLogWorkflow,
                    windowsWillSplitWimExpected: windowsWillSplitWim,
                    windowsWillCreateAutounattendExpected: windowsAutounattendConfiguration.shouldGenerateMacUSBFile,
                    windowsWillInstallMacUSBootExpected: resolvedWindowsBootMode == .bios,
                    shouldDetachMountPoint: shouldDetachMountPointAfterFinish,
                    targetWholeDiskBSDName: targetWholeDiskBSDNameForFinish,
                    needsPreformat: (targetDrive?.needsFormatting ?? false) && !isPPC,
                    onReset: {
                        NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                        self.isTabLocked = false
                        self.rootIsActive = false
                    },
                    onCancelRequested: showCreationProgressCancelAlert,
                    canCancelWorkflow: !didCancelCreation
                        && !navigateToFinish
                        && !isWindowsMacUSBootCancellationBlocked,
                    helperStageTitleKey: $helperStageTitleKey,
                    helperStatusKey: $helperStatusKey,
                    helperCurrentStageKey: $helperCurrentStageKey,
                    helperWriteSpeedText: $helperWriteSpeedText,
                    helperCopyProgressPercent: $helperCopyProgressPercent,
                    isHelperWorking: $isHelperWorking,
                    isCancelling: $isCancelling,
                    navigateToFinish: $navigateToFinish,
                    helperOperationFailed: $helperOperationFailed,
                    workflowResultDetailMessage: $workflowResultDetailMessage,
                    workflowResultErrorPresentation: $workflowResultErrorPresentation,
                    didCancelCreation: $didCancelCreation,
                    creationStartedAt: $usbProcessStartedAt
                ),
                isActive: $navigateToCreationProgress
            ) { EmptyView() }
            .hidden()
        )
        .onAppear {
            initializeMacOSRosettaStateIfNeeded()
            if isWindowsWorkflow {
                initializeWindowsBootModeSelectionIfNeeded()
                loadWindowsAutounattendConfiguration()
                InstallerSourceImageUnmountRegistry.shared.registerSourceImage(
                    path: sourceAppURL.path,
                    family: .windows,
                    mountHint: windowsMountedSourcePath,
                    reason: "installation_summary_on_appear",
                    stage: .usb
                )
            }
            if isLinuxWorkflow && !isRawImageWorkflow {
                InstallerSourceImageUnmountRegistry.shared.registerSourceImage(
                    path: sourceAppURL.path,
                    family: .linux,
                    mountHint: linuxFlowContext?.mountedImagePath,
                    reason: "installation_summary_on_appear",
                    stage: .usb
                )
            }
            menuState.setDownloaderAccessBlocked(true, reason: downloaderBlockReason)
            AppLogging.info("Entered USB creation summary.", stage: .usb, workflow: creationLogWorkflow)
            refreshRequiredPermissionsState()
            if isWindowsWorkflow {
                refreshWindowsPrerequisiteToolchainPresence()
            }
            if !isProcessing && !isHelperWorking && !isCancelled && !isUSBDisconnectedLock && !navigateToCreationProgress {
                startUSBMonitoring()
            }
        }
        .onChange(of: selectedWindowsBootMode) { mode in
            logWindowsBootModeChangeIfNeeded(mode)
        }
        .onDisappear {
            invalidateMacOSRosettaChecks()
            menuState.setDownloaderAccessBlocked(false, reason: downloaderBlockReason)
            stopUSBMonitoring()
            if !navigateToCreationProgress && !isHelperWorking {
                stopHelperWriteSpeedMonitoring()
            }
        }
    }

    private func refreshRequiredPermissionsState() {
        FullDiskAccessPermissionManager.shared.refreshState(trigger: .installationSummary)
        HelperServiceManager.shared.refreshBackgroundApprovalState()
    }
}

// --- KLASY POMOCNICZE W TYM PLIKU ---

struct WindowAccessor_Universal: NSViewRepresentable {
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
