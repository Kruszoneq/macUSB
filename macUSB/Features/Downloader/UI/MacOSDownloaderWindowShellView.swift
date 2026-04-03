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
                Text("Menedżer pobierania macOS")
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
                        Text("Zamknij")
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
        .onDisappear {
            logic.cancelDiscovery(updateState: false)
            downloadFlowModel.stop()
        }
    }

    var managerDescriptionText: String {
        if activeDownloadEntry == nil {
            return "Wybierz oficjalny instalator macOS lub OS X dostępny na serwerach Apple"
        }
        if downloadFlowModel.isFinished {
            return "Pobieranie zostało zakończone, a podsumowanie procesu znajdziesz poniżej"
        }
        return "Pobieranie i przygotowanie instalatora trwa, a postęp etapów jest widoczny poniżej"
    }

    var shouldConfirmCloseDuringDownload: Bool {
        activeDownloadEntry != nil && !downloadFlowModel.isFinished
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
            alert.informativeText = String(localized: "Jeśli zamkniesz okno teraz, pobieranie zostanie przerwane, a pobrane pliki pozostaną w folderze tymczasowym do czasu zamknięcia aplikacji")
        } else {
            alert.informativeText = String(localized: "Jeśli zamkniesz okno teraz, pobieranie zostanie przerwane, a pobrane pliki tymczasowe zostaną usunięte")
        }
        alert.addButton(withTitle: String(localized: "Kontynuuj pobieranie"))
        alert.addButton(withTitle: String(localized: "Anuluj pobieranie i zamknij"))
        return alert.runModal() == .alertSecondButtonReturn
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

    func supportsMontereyDownload(_ entry: MacOSInstallerEntry) -> Bool {
        let normalizedName = entry.name.lowercased()
        return normalizedName.contains("monterey") || entry.version.split(separator: ".").first == "12"
    }

    func handleDownloadTap(for entry: MacOSInstallerEntry) {
        guard supportsMontereyDownload(entry) else {
            AppLogging.info(
                "Pobieranie jest obecnie dostepne tylko dla macOS Monterey.",
                category: "Downloader"
            )
            return
        }

        activeDownloadEntry = entry
        downloadFlowModel.start(for: entry, using: logic)

        AppLogging.info(
            "Uruchomiono pobieranie Monterey dla \(entry.name) \(entry.version).",
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
            Text("Opcje listy systemów")
                .font(.headline)

            Toggle("Pokaż wszystkie dostępne wersje", isOn: $showAllAvailableVersions)
                .toggleStyle(.checkbox)

            #if DEBUG
            Divider()
                .padding(.vertical, 2)

            Text("DEBUG")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle("DEBUG: Nie usuwaj pobranych plików", isOn: $preserveDownloadedFilesInDebug)
                .toggleStyle(.checkbox)
            #endif

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Gotowe")
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
