import SwiftUI
import AppKit
import UserNotifications

struct MacOSDownloaderWindowShellView: View {
    let contentHeight: CGFloat
    let onClose: () -> Void

    @StateObject var logic = MacOSDownloaderLogic()
    @StateObject var downloadFlowModel = MontereyDownloadFlowModel()
    @State var isOptionsPresented = false
    @State var showAllAvailableVersions = false
    @State var selectedInstallerID: String?
    @State var activeDownloadEntry: MacOSInstallerEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Pobieranie systemu macOS"))
                    .font(.title3.weight(.semibold))
                Text(managerDescriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MacUSBDesignTokens.panelInnerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macUSBPanelSurface(.subtle)

            if let activeDownloadEntry {
                downloaderProgressSection(for: activeDownloadEntry)
            } else {
                installerSelectionSection
            }
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
            MacOSDownloaderOptionsSheetView(
                showAllAvailableVersions: $showAllAvailableVersions,
                preserveDownloadedFilesInDebug: $downloadFlowModel.preserveDownloadedFilesInDebug
            )
        }
        .task {
            logic.startDiscovery()
        }
        .onChange(of: logic.familyGroups) {
            ensureSelectedEntryIsVisible()
        }
        .onChange(of: showAllAvailableVersions) {
            ensureSelectedEntryIsVisible()
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
        }
        .onDisappear {
            logic.cancelDiscovery(updateState: false)
            downloadFlowModel.stop()
        }
    }

    var closeButtonTitle: String {
        shouldConfirmCloseDuringDownload
            ? String(localized: "Anuluj")
            : String(localized: "Zamknij")
    }

    var managerDescriptionText: String {
        if activeDownloadEntry == nil {
            return String(localized: "Wybierz instalator dostępny na serwerach Apple")
        }
        if downloadFlowModel.isFinished {
            return String(localized: "Pobieranie zakończone. Podsumowanie jest dostępne poniżej")
        }
        return String(localized: "Trwa pobieranie i przygotowywanie instalatora")
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
                    "Anulowano zamkniecie okna downloadera podczas aktywnego pobierania.",
                    category: "Downloader"
                )
                return
            }

            AppLogging.info(
                "Potwierdzono anulowanie pobierania i zamkniecie okna downloadera.",
                category: "Downloader"
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
        alert.messageText = String(localized: "Anulować pobieranie systemu?")
        if downloadFlowModel.shouldRetainSessionFilesForDebugMode() {
            alert.informativeText = String(localized: "Po zamknięciu okna pobieranie zostanie przerwane, a pliki tymczasowe pozostaną do czasu zamknięcia aplikacji")
        } else {
            alert.informativeText = String(localized: "Po zamknięciu okna pobieranie zostanie przerwane, a pliki tymczasowe zostaną usunięte")
        }
        alert.addButton(withTitle: String(localized: "Kontynuuj pobieranie"))
        alert.addButton(withTitle: String(localized: "Anuluj pobieranie i zamknij"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    func presentInsufficientDiskSpaceAlert(context: DiskSpaceAlertContext) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Za mało miejsca na dysku")
        alert.informativeText = String(
            format: String(localized: "Aby rozpocząć pobieranie, potrzebujesz więcej wolnego miejsca na dysku.\n\nWymagane minimum: %@. Dostępne: %@.\n\nZwolnij miejsce i spróbuj ponownie."),
            context.requiredMinimumText,
            context.availableText
        )
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
        handleCloseRequest()
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
        if logic.isOldestDownloadTarget(entry) {
            return true
        }

        let normalizedName = entry.name.lowercased()
        let major = entry.version.split(separator: ".").first.map(String.init) ?? ""
        let supportedMajors: Set<String> = ["11", "12", "13", "14", "15", "26"]
        if supportedMajors.contains(major) {
            return true
        }
        if normalizedName.contains("catalina") && entry.version.hasPrefix("10.15") {
            return true
        }
        if normalizedName.contains("mojave") && entry.version.hasPrefix("10.14") {
            return true
        }
        if normalizedName.contains("high sierra") && entry.version.hasPrefix("10.13") {
            return true
        }
        return normalizedName.contains("big sur")
            || normalizedName.contains("catalina")
            || normalizedName.contains("mojave")
            || normalizedName.contains("high sierra")
            || normalizedName.contains("monterey")
            || normalizedName.contains("ventura")
            || normalizedName.contains("sonoma")
            || normalizedName.contains("sequoia")
            || normalizedName.contains("tahoe")
    }

    func handleDownloadTap(for entry: MacOSInstallerEntry) {
        guard supportsProductionDownload(entry) else {
            AppLogging.info(
                "Pobieranie jest obecnie dostepne tylko dla: macOS High Sierra, Mojave, Catalina, Big Sur, Monterey, Ventura, Sonoma, Sequoia i Tahoe.",
                category: "Downloader"
            )
            return
        }

        activeDownloadEntry = entry
        downloadFlowModel.start(for: entry, using: logic)

        AppLogging.info(
            "Uruchomiono pobieranie systemu dla \(entry.name) \(entry.version).",
            category: "Downloader"
        )
    }

    func sendDownloadCompletionNotificationIfInactive(for entry: MacOSInstallerEntry) {
        guard !NSApp.isActive else { return }

        let title = String(localized: "Pobieranie zakończone")
        let body = String(
            format: String(localized: "Pobieranie systemu %@ %@ zostało zakończone pomyślnie."),
            entry.name,
            entry.version
        )

        NotificationPermissionManager.shared.shouldDeliverInAppNotification { shouldDeliver in
            guard shouldDeliver else { return }
            scheduleSystemNotification(title: title, body: body)
            AppLogging.info(
                "Wyslano powiadomienie systemowe o zakonczeniu pobierania \(entry.name) \(entry.version).",
                category: "Downloader"
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

private struct MacOSDownloaderOptionsSheetView: View {
    @Binding var showAllAvailableVersions: Bool
    @Binding var preserveDownloadedFilesInDebug: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Opcje pobierania"))
                .font(.headline)

            Toggle(String(localized: "Pokaż wszystkie wersje"), isOn: $showAllAvailableVersions)
                .toggleStyle(.checkbox)

            #if DEBUG
            HStack(spacing: 10) {
                Capsule()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(height: 1)
                Text(String(localized: "Deweloperskie"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Capsule()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(height: 1)
            }
            .padding(.vertical, 2)

            Toggle(String(localized: "Zachowaj pobrane pliki (Debug)"), isOn: $preserveDownloadedFilesInDebug)
                .toggleStyle(.checkbox)
            #endif

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "OK"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .macUSBPrimaryButtonStyle()
            }
        }
        .padding(18)
        .frame(width: 420, height: 240)
    }
}
