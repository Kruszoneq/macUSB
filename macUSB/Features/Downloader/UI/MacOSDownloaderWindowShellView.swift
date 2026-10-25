import SwiftUI
import AppKit
import UserNotifications

struct MacOSDownloaderWindowShellView: View {
    let contentHeight: CGFloat
    let onClose: () -> Void

    @StateObject var logic = MacOSDownloaderLogic()
    @StateObject var downloadFlowModel = MontereyDownloadFlowModel()
    @StateObject var prerequisiteController = MacOSDownloaderPrerequisiteController()
    @State var isOptionsPresented = false
    @State var showAllAvailableVersions = false
    @State var showBetaVersions = false
    @State var createDiskImage = false
    @State var diskImageDestinationDirectoryURL: URL?
    @State var selectedInstallerID: String?
    @State var activeDownloadEntry: MacOSInstallerEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "downloader.window.title", table: "Downloader"))
                    .font(.title3.weight(.semibold))
                Text(managerDescriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MacUSBDesignTokens.panelInnerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macUSBPanelSurface(.subtle)

            ZStack(alignment: .topLeading) {
                if let activeDownloadEntry {
                    downloaderProgressSection(for: activeDownloadEntry)
                        .transition(downloaderScreenTransition)
                } else {
                    installerSelectionSection
                        .transition(downloaderScreenTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, MacUSBDesignTokens.contentHorizontalPadding)
        .padding(.top, MacUSBDesignTokens.contentVerticalPadding)
        .frame(
            width: MacUSBDesignTokens.windowWidth,
            height: contentHeight,
            alignment: .topLeading
        )
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    handleCloseRequest()
                } label: {
                    HStack {
                        Text(closeButtonTitle)
                        Image(systemName: "xmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                }
                .macUSBPrimaryButtonStyle()
            }
        }
        .sheet(isPresented: $isOptionsPresented) {
            MacOSDownloaderDiskImageOptionsView(
                showAllAvailableVersions: Binding(
                    get: { showAllAvailableVersions },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.24)) {
                            showAllAvailableVersions = newValue
                        }
                    }
                ),
                showBetaVersions: Binding(
                    get: { showBetaVersions },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.24)) {
                            showBetaVersions = newValue
                        }
                    }
                ),
                createDiskImage: $createDiskImage,
                diskImageDestinationDirectoryURL: $diskImageDestinationDirectoryURL,
                preserveDownloadedFilesInDebug: $downloadFlowModel.preserveDownloadedFilesInDebug
            )
        }
        .task {
            logic.startDiscovery()
            prerequisiteController.refresh(trigger: .initialPresentation)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            prerequisiteController.refresh(trigger: .appActivation)
        }
        .onChange(of: logic.familyGroups) {
            ensureSelectedEntryIsVisible()
        }
        .onChange(of: logic.state) {
            presentUnrecognizedLocalInstallersAlertIfNeeded()
        }
        .onChange(of: showAllAvailableVersions) {
            ensureSelectedEntryIsVisible()
        }
        .onChange(of: showBetaVersions) {
            selectedInstallerID = nil
            AppLogging.info(
                "Public Beta visibility changed to \(showBetaVersions). Applied the animated filter to current results without refreshing Apple catalogs.",
                stage: .downloader
            )
        }
        .onChange(of: downloadFlowModel.isFinished) {
            guard downloadFlowModel.isFinished,
                  downloadFlowModel.workflowState == .completed,
                  let activeDownloadEntry
            else { return }
            sendDownloadCompletionNotificationIfInactive(for: activeDownloadEntry)
        }
        .onChange(of: downloadFlowModel.pendingDiskSpaceAlert) {
            guard let context = downloadFlowModel.pendingDiskSpaceAlert else { return }
            presentInsufficientDiskSpaceAlert(context: context)
            downloadFlowModel.pendingDiskSpaceAlert = nil
            if context.diskImageLocation != nil {
                returnToInstallerListAfterDiskImagePreflight()
            }
        }
        .onChange(of: downloadFlowModel.pendingDiskImageFolderUnavailableAlert) {
            guard downloadFlowModel.pendingDiskImageFolderUnavailableAlert else { return }
            presentDiskImageFolderUnavailableAlert()
            returnToInstallerListAfterDiskImagePreflight()
        }
        .onChange(of: downloadFlowModel.didCancelDiskImagePreflight) {
            guard downloadFlowModel.didCancelDiskImagePreflight else { return }
            returnToInstallerListAfterDiskImagePreflight()
        }
        .onDisappear {
            prerequisiteController.invalidate()
            logic.cancelDiscovery(updateState: false)
            downloadFlowModel.stop()
        }
    }

    var closeButtonTitle: String {
        shouldConfirmCloseDuringDownload
            ? String(localized: "downloader.action.cancel", table: "Downloader")
            : String(localized: "downloader.action.close", table: "Downloader")
    }

    var downloaderScreenTransition: AnyTransition {
        .opacity.combined(
            with: .scale(scale: MacUSBDesignTokens.stageTransitionScale)
        )
    }

    var managerDescriptionText: String {
        if activeDownloadEntry == nil {
            return String(localized: "downloader.window.selection.description", table: "Downloader")
        }
        if downloadFlowModel.isFinished {
            return String(localized: "downloader.window.summary.description", table: "Downloader")
        }
        return String(localized: "downloader.window.process.description", table: "Downloader")
    }

    var shouldConfirmCloseDuringDownload: Bool {
        activeDownloadEntry != nil
            && !downloadFlowModel.isFinished
            && downloadFlowModel.workflowState == .running
    }

    func handleCloseRequest() {
        if shouldConfirmCloseDuringDownload {
            let shouldClose = presentCloseDownloadConfirmationAlert()
            guard shouldClose else {
                AppLogging.info(
                    "Cancelled closing the downloader window during an active download.",
                    stage: .downloader
                )
                return
            }

            AppLogging.info(
                "Confirmed download cancellation and closing the downloader window.",
                stage: .downloader
            )
            downloadFlowModel.stop()
            if !downloadFlowModel.shouldRetainSessionFilesForDebugMode() {
                downloadFlowModel.cleanupTemporaryDownloadsFolder()
            }
            activeDownloadEntry = nil
        }

        logic.cancelDiscovery()
        onClose()
    }

    func presentCloseDownloadConfirmationAlert() -> Bool {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "downloader.cancellation.alert.title", table: "Downloader")
        if downloadFlowModel.shouldRetainSessionFilesForDebugMode() {
            alert.informativeText = "When you close the window, the download will stop and the temporary files will remain until you close the application"
        } else {
            alert.informativeText = String(localized: "downloader.cancellation.alert.message", table: "Downloader")
        }
        alert.addButton(withTitle: String(localized: "downloader.cancellation.continue.action", table: "Downloader"))
        alert.addButton(withTitle: String(localized: "downloader.cancellation.confirm.action", table: "Downloader"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    func presentUnrecognizedLocalInstallersAlertIfNeeded() {
        guard
            logic.state == .loaded,
            logic.unrecognizedLocalInstallerCount > 0,
            MacOSDownloaderWindowManager.shared.claimUnrecognizedLocalInstallerAlertPresentation()
        else {
            return
        }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "downloader.local_installers.unrecognized_title", table: "Downloader"
        )
        alert.informativeText = String(
            format: String(
                localized: "downloader.local_installers.unrecognized_message", table: "Downloader"
            ),
            String(logic.unrecognizedLocalInstallerCount)
        )
        alert.addButton(withTitle: String(localized: "downloader.local_installers.acknowledge.action", table: "Downloader"))
        alert.runModal()
    }

    func presentRedownloadConfirmationAlert() -> Bool {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "downloader.local_installers.redownload_title", table: "Downloader"
        )
        alert.informativeText = String(
            localized: "downloader.local_installers.redownload_message", table: "Downloader"
        )
        alert.addButton(
            withTitle: String(
                localized: "downloader.local_installers.redownload_cancel", table: "Downloader"
            )
        )
        alert.addButton(
            withTitle: String(
                localized: "downloader.local_installers.redownload_confirm", table: "Downloader"
            )
        )
        return alert.runModal() == .alertSecondButtonReturn
    }

    func presentIntelBootableInstallerWarningAlert() -> Bool {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "downloader.intel_bootable_installer_warning.title", table: "Downloader"
        )
        alert.informativeText = String(
            localized: "downloader.intel_bootable_installer_warning.message", table: "Downloader"
        )
        alert.addButton(
            withTitle: String(
                localized: "downloader.intel_bootable_installer_warning.confirm", table: "Downloader"
            )
        )
        alert.addButton(
            withTitle: String(
                localized: "downloader.intel_bootable_installer_warning.cancel", table: "Downloader"
            )
        )
        return alert.runModal() == .alertFirstButtonReturn
    }

    func requiresIntelBootableInstallerWarning(_ entry: MacOSInstallerEntry) -> Bool {
        guard MacHardwareArchitecture.current == .intel else {
            return false
        }
        guard
            let majorVersionText = entry.version.split(separator: ".").first,
            let majorVersion = Int(majorVersionText)
        else {
            return false
        }
        return majorVersion >= 27
    }

    func ensureSelectedEntryIsVisible() {
        guard let selectedInstallerID else { return }
        let visibleIDs = Set(visibleFamilyGroups.flatMap { group in
            group.entries.map(\.id)
        })

        if !visibleIDs.contains(selectedInstallerID) {
            self.selectedInstallerID = nil
        }
    }

    func supportsProductionDownload(_ entry: MacOSInstallerEntry) -> Bool {
        logic.supportsProductionDownload(entry)
    }

    func loggingWorkflow(for entry: MacOSInstallerEntry) -> AppLogging.Workflow {
        if logic.isOldestDownloadTarget(entry) { return .oldest }
        return logic.isLegacyAssemblyTarget(entry) ? .legacy : .modern
    }

    func handleDownloadTap(for entry: MacOSInstallerEntry) {
        guard supportsProductionDownload(entry) else {
            AppLogging.info(
                "Download is currently available only for: macOS High Sierra, Mojave, Catalina, Big Sur, Monterey, Ventura, Sonoma, Sequoia, Tahoe, and Golden Gate.",
                stage: .downloader
            )
            return
        }

        guard !prerequisiteController.isChecking else {
            AppLogging.info(
                "Skipped downloader prerequisite refresh because a check is already running.",
                stage: .downloader
            )
            return
        }

        prerequisiteController.refresh(trigger: .downloadAction) { snapshot in
            guard snapshot.allowsDownload else {
                AppLogging.info(
                    "Download start blocked because downloader prerequisites are not met.",
                    stage: .downloader
                )
                presentDownloaderPrerequisiteAlert(for: snapshot)
                return
            }

            continueDownloadTap(for: entry)
        }
    }

    private func continueDownloadTap(for entry: MacOSInstallerEntry) {

        if requiresIntelBootableInstallerWarning(entry) {
            guard presentIntelBootableInstallerWarningAlert() else {
                AppLogging.info(
                    "Cancelled download of installer \(entry.name) \(entry.version) (\(entry.build)) after the Intel Mac bootable USB warning.",
                    stage: .downloader, workflow: loggingWorkflow(for: entry)
                )
                return
            }
            AppLogging.info(
                "Confirmed download of installer \(entry.name) \(entry.version) (\(entry.build)) despite the Intel Mac bootable USB warning.",
                stage: .downloader, workflow: loggingWorkflow(for: entry)
            )
        }

        if entry.isDownloaded {
            guard presentRedownloadConfirmationAlert() else {
                AppLogging.info(
                    "Cancelled redownload of locally detected installer \(entry.name) \(entry.version) (\(entry.build)).",
                    stage: .downloader, workflow: loggingWorkflow(for: entry)
                )
                return
            }
            AppLogging.info(
                "Confirmed redownload of locally detected installer \(entry.name) \(entry.version) (\(entry.build)).",
                stage: .downloader, workflow: loggingWorkflow(for: entry)
            )
        }

        withAnimation(MacUSBDesignTokens.stageTransitionAnimation) {
            activeDownloadEntry = entry
        }
        let diskImageConfiguration = MacOSDiskImageConfiguration(
            isEnabled: createDiskImage,
            destinationDirectoryURL: createDiskImage
                ? diskImageDestinationDirectoryURL
                : nil
        )
        downloadFlowModel.start(
            for: entry,
            using: logic,
            diskImageConfiguration: diskImageConfiguration,
            collisionDecision: { context in
                presentDiskImageCollisionAlert(context: context)
            }
        )

        AppLogging.info(
            "Started system download for \(entry.name) \(entry.version).",
            stage: .downloader, workflow: loggingWorkflow(for: entry)
        )
    }

    func sendDownloadCompletionNotificationIfInactive(for entry: MacOSInstallerEntry) {
        guard !NSApp.isActive else { return }

        let title = String(localized: "downloader.notification.completed.title", table: "Downloader")
        let body = String(
            format: String(localized: "downloader.notification.completed.message", table: "Downloader"),
            entry.name,
            entry.version
        )

        NotificationPermissionManager.shared.shouldDeliverInAppNotification { shouldDeliver in
            guard shouldDeliver else { return }
            scheduleSystemNotification(title: title, body: body)
            AppLogging.info(
                "Sent system notification for completed download of \(entry.name) \(entry.version).",
                stage: .downloader, workflow: loggingWorkflow(for: entry)
            )
        }
    }

    func scheduleSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "macUSB.downloader.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

}
