import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct SystemAnalysisView: View {
    
    @ObservedObject private var menuState = MenuState.shared
    @Binding var isTabLocked: Bool
    @StateObject private var logic = AnalysisLogic()
    @State private var shouldResetToStart: Bool = false
    
    @State private var selectedDriveDisplayNameSnapshot: String? = nil
    @State private var selectedDriveForInstallationSnapshot: USBDrive? = nil
    @State private var linuxFlowContextSnapshot: LinuxInstallationFlowContext? = nil
    @State private var navigateToInstall: Bool = false
    @State private var isDragTargeted: Bool = false
    @State private var analysisWindowHandler: AnalysisWindowHandler?
    @State private var hostingWindow: NSWindow? = nil
    @State private var lastAPFSAlertedDriveURL: URL? = nil
    
    let driveRefreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private var visualMode: VisualSystemMode { currentVisualMode() }
    private var sectionIconFont: Font { .title3 }
    private func sectionDivider(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
    
    private func updateMenuState() {
        // Enable only when analysis has finished with a file that is NOT supported by the app.
        // Hide/disable when the selected system is supported (including PPC flow) or analysis not finished.
        let analysisFinished = !logic.isAnalyzing
        let hasAnySelection = !logic.selectedFilePath.isEmpty || logic.selectedFileUrl != nil
        let isValidSelection = (logic.sourceAppURL != nil) || logic.isPPC || logic.isMavericks || logic.isLinuxDetected

        let unrecognizedBlocking = (!logic.isSystemDetected
                                    && !logic.recognizedVersion.isEmpty
                                    && logic.sourceAppURL == nil
                                    && !logic.showUnsupportedMessage
                                    && !logic.isLinuxDetected)

        let recognizedUnsupported = (!logic.isSystemDetected
                                     && !logic.recognizedVersion.isEmpty
                                     && logic.showUnsupportedMessage)

        MenuState.shared.skipAnalysisEnabled = analysisFinished && hasAnySelection && !isValidSelection && (unrecognizedBlocking || recognizedUnsupported)
    }
    
    private func presentMavericksDialog() {
        guard let window = hostingWindow else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "Wykryto system OS X Mavericks", comment: "Mavericks detected alert title")
        alert.informativeText = String(localized: "Upewnij się, że wybrany obraz systemu pochodzi ze strony Mavericks Forever. Inne wersje mogą powodować błędy w trakcie tworzenia instalatora na nośniku USB.", comment: "Mavericks detected alert description")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.beginSheetModal(for: window) { _ in
            logic.shouldShowMavericksDialog = false
        }
    }

    private func presentAlreadyMountedSourceDialog() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Wybrany obraz jest już zamontowany", comment: "Already mounted CDR/ISO alert title")
        alert.informativeText = String(localized: "Wybrany plik .cdr lub .iso jest już zamontowany w systemie macOS. Odmontuj ten obraz, a następnie wybierz „Analizuj” ponownie.", comment: "Already mounted CDR/ISO alert description")
        alert.addButton(withTitle: String(localized: "OK"))

        let handleClose: (NSApplication.ModalResponse) -> Void = { _ in
            logic.shouldShowAlreadyMountedSourceAlert = false
        }

        if let window = hostingWindow {
            alert.beginSheetModal(for: window, completionHandler: handleClose)
        } else {
            handleClose(alert.runModal())
        }
    }

    private func presentAPFSDriveDialog() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Wybrano nośnik APFS")
        alert.informativeText = String(localized: "Nośniki APFS nie mogą zostać automatycznie przeformatowane przez macUSB. Otwórz Narzędzie dyskowe i sformatuj wybrany nośnik ręcznie do dowolnego formatu innego niż APFS, a następnie wybierz go ponownie.")
        alert.addButton(withTitle: String(localized: "Otwórz Narzędzie dyskowe"))
        alert.addButton(withTitle: String(localized: "Zamknij"))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            self.openDiskUtility()
        }

        if let window = hostingWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func openDiskUtility() {
        let candidates = [
            "/System/Applications/Utilities/Disk Utility.app",
            "/Applications/Utilities/Disk Utility.app"
        ].map { URL(fileURLWithPath: $0) }

        for appURL in candidates where NSWorkspace.shared.open(appURL) {
            return
        }
    }

    private func handleAPFSSelectionChange() {
        guard isAPFSSelected else {
            lastAPFSAlertedDriveURL = nil
            return
        }

        guard let selectedURL = logic.selectedDrive?.url else { return }
        guard lastAPFSAlertedDriveURL != selectedURL else { return }
        lastAPFSAlertedDriveURL = selectedURL
        presentAPFSDriveDialog()
    }

    private func consumePendingDownloaderInstallerAndAnalyze() {
        guard let installerURL = AnalysisSelectionHandoff.shared.consumePendingInstallerURL() else { return }
        logic.applySelectedURLAndStartAnalysis(installerURL)
    }

    private func handleViewAppear() {
        logic.refreshDrives()
        updateMenuState()
        consumePendingDownloaderInstallerAndAnalyze()
        if logic.shouldShowMavericksDialog {
            presentMavericksDialog()
        }
    }
    
    private var fileRequirementsBox: some View {
        StatusCard(tone: .neutral, density: .compact) {
            HStack(alignment: .top) {
                Image(systemName: "info.circle.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Wymagania").font(.headline).foregroundColor(.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("• Wybrany plik musi zawierać instalator macOS, Mac OS X lub Linux")
                        Text("• Dozwolone formaty plików to .dmg, .iso, .cdr oraz .app")
                        Text("• Wymagane jest co najmniej 15 GB wolnego miejsca na dysku twardym")
                        Text("• Brak instalatora? Użyj przycisku „Pobierz”")
                    }
                    .font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
    }

    private var fileSelectionControls: some View {
        HStack {
            TextField(String(localized: "Ścieżka..."), text: $logic.selectedFilePath)
                .textFieldStyle(.roundedBorder)
                .disabled(true)
            Button(String(localized: "Wybierz")) { logic.selectDMGFile() }
            Button(String(localized: "Pobierz")) { MacOSDownloaderWindowManager.shared.present() }
                .disabled(menuState.isDownloaderAccessBlocked)
            Button(String(localized: "Analizuj")) { logic.startAnalysis() }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(logic.selectedFilePath.isEmpty || logic.isAnalyzing)
        }
    }

    private var fileSelectionSection: some View {
        VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
            sectionDivider("Wybór pliku")
            fileRequirementsBox
            fileSelectionControls
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDragTargeted ? Color.accentColor : Color.clear, lineWidth: isDragTargeted ? 3 : 0)
                .background(isDragTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .cornerRadius(MacUSBDesignTokens.panelCornerRadius(for: visualMode))
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            logic.handleDrop(providers: providers)
        }
    }

    private var waitingForFileHint: some View {
        StatusCard(tone: .subtle, density: .compact) {
            HStack(alignment: .center) {
                Image(systemName: "doc.badge.plus").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Oczekiwanie na plik .dmg, .iso, .cdr lub .app...").font(.subheadline).foregroundColor(.secondary)
                    Text("Wybierz go ręcznie lub przeciągnij powyżej").font(.caption).foregroundColor(.secondary.opacity(0.8))
                }
                Spacer()
            }
        }
        .transition(.opacity)
    }

    private var analyzingStatusView: some View {
        StatusCard(tone: .active) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 15) {
                    Image(systemName: "internaldrive").font(sectionIconFont).foregroundColor(.accentColor).frame(width: MacUSBDesignTokens.iconColumnWidth)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Analizowanie").font(.headline)
                        HStack(spacing: 8) {
                            Text("Trwa analizowanie pliku, proszę czekać").font(.subheadline).foregroundColor(.secondary)
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            }
        }
        .transition(.opacity)
    }

    private var detectedOrUnsupportedView: some View {
        let isValid = (logic.sourceAppURL != nil) || logic.isPPC || logic.isLinuxDetected
        let unsupportedText = logic.isUnsupportedSierra
            ? String(localized: "Ta wersja systemu macOS Sierra nie jest wspierana przez aplikację. Potrzebna jest nowsza wersja instalatora.", comment: "Unsupported Sierra (not 12.6.06) message")
            : String(localized: "Wybrany system nie jest wspierany przez aplikację", comment: "Generic unsupported system message")

        return VStack(alignment: .leading, spacing: MacUSBDesignTokens.bottomBarContentSpacing) {
            StatusCard(tone: isValid ? .success : .error) {
                HStack(alignment: .center) {
                    if isValid, let detectedIcon = logic.detectedSystemIcon {
                        Image(nsImage: detectedIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                    } else if logic.isLinuxDetected {
                        Image(systemName: "desktopcomputer")
                            .font(sectionIconFont)
                            .foregroundColor(.green)
                            .frame(width: MacUSBDesignTokens.iconColumnWidth)
                    } else {
                        Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(sectionIconFont)
                            .foregroundColor(isValid ? .green : .red)
                            .frame(width: MacUSBDesignTokens.iconColumnWidth)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(isValid ? "Pomyślnie wykryto system" : "Błąd analizy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(isValid ? (logic.recognizedVersion.isEmpty ? String(localized: "Wykryto kompatybilny instalator") : logic.recognizedVersion) : unsupportedText)
                            .font(.headline)
                            .foregroundColor(isValid ? .green : .red)
                    }
                    Spacer()
                }
            }

            if isValid && (logic.userSkippedAnalysis || ((logic.legacyArchInfo ?? "").isEmpty == false)) {
                StatusCard(tone: .subtle, density: .compact) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(sectionIconFont)
                            .foregroundColor(.secondary)
                            .frame(width: MacUSBDesignTokens.iconColumnWidth)
                        VStack(alignment: .leading, spacing: 4) {
                            if logic.userSkippedAnalysis {
                                Text(String(localized: "Analiza nie została wykonana - wybór użytkownika"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if let arch = logic.legacyArchInfo, !arch.isEmpty {
                                Text(arch)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }

            if !isValid && logic.showUnsupportedMessage {
                StatusCard(tone: .subtle, density: .compact) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(sectionIconFont)
                            .foregroundColor(.secondary)
                            .frame(width: MacUSBDesignTokens.iconColumnWidth)
                        Text(unsupportedText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
        .transition(.opacity)
    }

    private var navigationBackgroundLink: some View {
        Group {
            if let sourceURL = logic.sourceAppURL ?? logic.linuxInstallationFlowContext?.sourceImageURL {
                NavigationLink(
                    destination: UniversalInstallationView(
                        sourceAppURL: sourceURL,
                        targetDrive: selectedDriveForInstallationSnapshot,
                        targetDriveDisplayName: selectedDriveDisplayNameSnapshot,
                        systemName: logic.recognizedVersion,
                        detectedSystemIcon: logic.detectedSystemIcon,
                        originalImageURL: logic.selectedFileUrl,
                        linuxFlowContext: linuxFlowContextSnapshot,
                        needsCodesign: logic.needsCodesign,
                        isLegacySystem: logic.isLegacyDetected,
                        isRestoreLegacy: logic.isRestoreLegacy,
                        isCatalina: logic.isCatalina,
                        isSierra: logic.isSierra,
                        isMavericks: logic.isMavericks,
                        isPPC: logic.isPPC,
                        rootIsActive: $navigateToInstall,
                        isTabLocked: $isTabLocked
                    ),
                    isActive: $navigateToInstall
                ) { EmptyView() }
                .hidden()
            }
        }
    }

    private var windowAccessorBackground: some View {
        WindowAccessor_System { window in
            if self.analysisWindowHandler == nil {
                let handler = AnalysisWindowHandler(
                    onCleanup: {
                        if let path = self.logic.mountedDMGPath {
                            let task = Process(); task.launchPath = "/usr/bin/hdiutil"; task.arguments = ["detach", path, "-force"]; try? task.run(); task.waitUntilExit()
                        }
                    }
                )
                window.delegate = handler
                self.analysisWindowHandler = handler
                self.hostingWindow = window
            }
        }
    }

    private var canUseUSBSelection: Bool {
        ((logic.sourceAppURL != nil) || logic.isPPC || logic.isLinuxDetected)
            && (logic.isSystemDetected || logic.isPPC || logic.isMavericks || logic.isLinuxDetected)
    }

    private var isAPFSSelected: Bool {
        logic.selectedDrive?.fileSystemFormat == .apfs
    }

    private var canProceedToInstall: Bool {
        canUseUSBSelection
            && logic.selectedDrive != nil
            && logic.capacityCheckFinished
            && logic.isCapacitySufficient
            && !isAPFSSelected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: MacUSBDesignTokens.contentSectionSpacing) {
                        fileSelectionSection

                        if logic.selectedFilePath.isEmpty {
                            waitingForFileHint
                        } else {
                            if logic.isAnalyzing {
                                analyzingStatusView
                            }

                            if !logic.recognizedVersion.isEmpty && !logic.isAnalyzing {
                                detectedOrUnsupportedView
                            }
                        }

                        Spacer().frame(height: 12)
                        usbSelectionSection
                            .id("usbSection")
                    }
                    .padding(.horizontal, MacUSBDesignTokens.contentHorizontalPadding)
                    .padding(.vertical, MacUSBDesignTokens.contentVerticalPadding)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button(action: {
                    selectedDriveDisplayNameSnapshot = logic.selectedDrive?.displayName
                    selectedDriveForInstallationSnapshot = logic.selectedDriveForInstallation
                    linuxFlowContextSnapshot = logic.linuxInstallationFlowContext
                    isTabLocked = true
                    navigateToInstall = true
                }) {
                    HStack { Text("Przejdź dalej"); Image(systemName: "arrow.right.circle.fill") }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
                .macUSBPrimaryButtonStyle(isEnabled: canProceedToInstall)
                .disabled(!canProceedToInstall)
            }
        }
        .background(navigationBackgroundLink)
        .background(windowAccessorBackground)
        .onReceive(driveRefreshTimer) { _ in
            logic.refreshDrives()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macUSBResetToStart)) { _ in
            // Reset logic state and UI as if first launch
            logic.resetAll()
            isTabLocked = false
            navigateToInstall = false
            selectedDriveDisplayNameSnapshot = nil
            selectedDriveForInstallationSnapshot = nil
            linuxFlowContextSnapshot = nil
            MenuState.shared.skipAnalysisEnabled = false
        }
        .onChange(of: logic.showUnsupportedMessage) { _ in updateMenuState() }
        .onChange(of: logic.recognizedVersion) { _ in updateMenuState() }
        .onChange(of: logic.isAnalyzing) { _ in updateMenuState() }
        .onChange(of: logic.isSystemDetected) { _ in updateMenuState() }
        .onChange(of: logic.selectedFilePath) { _ in updateMenuState() }
        .onChange(of: logic.isPPC) { _ in updateMenuState() }
        .onChange(of: logic.isLinuxDetected) { _ in updateMenuState() }
        .onChange(of: logic.sourceAppURL) { _ in updateMenuState() }
        .onChange(of: logic.shouldShowMavericksDialog) { show in
            if show { presentMavericksDialog() }
        }
        .onChange(of: logic.shouldShowAlreadyMountedSourceAlert) { show in
            if show { presentAlreadyMountedSourceDialog() }
        }
        .onChange(of: logic.selectedDrive?.url) { _ in
            handleAPFSSelectionChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macUSBStartTigerMultiDVD)) { _ in
            logic.forceTigerMultiDVDSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macUSBStartLinuxManualSelection)) { _ in
            logic.forceLinuxManualSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macUSBApplyPendingDownloaderInstaller)) { _ in
            consumePendingDownloaderInstallerAndAnalyze()
        }
        .onAppear {
            handleViewAppear()
        }
        .navigationTitle("Konfiguracja źródła i celu")
        .navigationBarBackButtonHidden(true)
    }
    
    var usbSelectionSection: some View {
        SystemAnalysisUSBSectionView(
            logic: logic,
            sectionIconFont: sectionIconFont,
            onOpenDiskUtility: openDiskUtility,
            isSelectionEnabled: canUseUSBSelection
        )
    }
}

struct SystemAnalysisUSBSectionView: View {
    @ObservedObject var logic: AnalysisLogic
    let sectionIconFont: Font
    let onOpenDiskUtility: () -> Void
    let isSelectionEnabled: Bool

    private var isAPFSSelected: Bool {
        logic.selectedDrive?.fileSystemFormat == .apfs
    }

    private var unreadableUSBDescription: String {
        if logic.unreadableExternalUSBMediaCount > 1 {
            return String(localized: "Do Maca są podłączone zewnętrzne nośniki USB, których macOS nie może odczytać. Otwórz Narzędzie dyskowe i wymaż je do formatu obsługiwanego przez macOS, a następnie wybierz nośnik ponownie.")
        }

        return String(localized: "Do Maca jest podłączony zewnętrzny nośnik USB, którego macOS nie może odczytać. Otwórz Narzędzie dyskowe i wymaż nośnik do formatu obsługiwanego przez macOS, a następnie wybierz go ponownie.")
    }

    private func sectionDivider(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
            sectionDivider("Wybór nośnika USB")
            StatusCard(tone: .neutral, density: .compact) {
                HStack(alignment: .top) {
                    Image(systemName: "externaldrive.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Wymagania sprzętowe").font(.headline)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                String(
                                    format: String(localized: "• Do utworzenia instalatora potrzebny jest nośnik USB o pojemności minimum %@ GB"),
                                    logic.requiredUSBCapacityDisplayValue
                                )
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            Text("• Zalecane jest użycie dysku w standardzie USB 3.0 lub szybszym").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Wybierz docelowy nośnik USB:").font(.subheadline)
                if logic.availableDrives.isEmpty && !logic.hasUnreadableExternalUSBMedia {
                    StatusCard(tone: .error, density: .compact) {
                        HStack {
                            Image(systemName: "externaldrive.badge.xmark").font(sectionIconFont).foregroundColor(.red).frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading) {
                                Text("Nie wykryto nośnika USB").font(.headline).foregroundColor(.red)
                                Text("Podłącz nośnik USB i poczekaj na wykrycie...").font(.caption).foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                } else if !logic.availableDrives.isEmpty {
                    HStack {
                        Picker("", selection: $logic.selectedDrive) {
                            Text("Wybierz...").tag(nil as USBDrive?)
                            ForEach(logic.availableDrives) { drive in Text(drive.displayName).tag(drive as USBDrive?) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .disabled(!isSelectionEnabled)
            .opacity(isSelectionEnabled ? 1.0 : 0.5)
            .onChange(of: logic.selectedDrive) { _ in logic.checkCapacity() }

            if logic.hasUnreadableExternalUSBMedia {
                StatusCard(tone: .warning, density: .compact) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(sectionIconFont)
                                .foregroundColor(.orange)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Wykryto nieczytelny nośnik USB")
                                    .font(.headline)
                                    .foregroundColor(.orange)

                                Text(unreadableUSBDescription)
                                    .font(.subheadline)
                                    .foregroundColor(.orange.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }

                        Button(action: onOpenDiskUtility) {
                            HStack(spacing: 8) {
                                Image(systemName: "externaldrive")
                                Text("Otwórz Narzędzie dyskowe")
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundColor(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .macUSBSecondaryButtonStyle()
                        .tint(.orange)
                    }
                }
                .transition(.opacity)
            }

            if logic.selectedDrive != nil {
                if isAPFSSelected {
                    StatusCard(tone: .error, density: .compact) {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(sectionIconFont)
                                .foregroundColor(.red)
                                .frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading) {
                                Text("Wybrano nośnik APFS")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text("Wybrany nośnik korzysta z formatu APFS. Aby kontynuować, sformatuj go ręcznie w Narzędziu dyskowym do dowolnego formatu innego niż APFS.")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            Spacer()
                        }
                    }
                    .transition(.opacity)
                }
                if logic.capacityCheckFinished && !logic.isCapacitySufficient {
                    StatusCard(tone: .error, density: .compact) {
                        HStack {
                            Image(systemName: "xmark.circle.fill").font(sectionIconFont).foregroundColor(.red).frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading) {
                                Text("Wybrany nośnik USB ma za małą pojemność").font(.headline).foregroundColor(.red)
                                Text(
                                    String(
                                        format: String(localized: "Wymagane jest minimum %@ GB."),
                                        logic.requiredUSBCapacityDisplayValue
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                    .transition(.opacity)
                }
                if logic.capacityCheckFinished && logic.isCapacitySufficient && !isAPFSSelected {
                    VStack(alignment: .leading, spacing: 15) {
                        StatusCard(tone: .warning, density: .compact) {
                            HStack(alignment: .center) {
                                Image(systemName: "exclamationmark.triangle.fill").font(sectionIconFont).foregroundColor(.orange).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading) {
                                    Text("UWAGA!").font(.headline).foregroundColor(.orange)
                                    Text("Wszystkie pliki na wybranym nośniku USB zostaną bezpowrotnie usunięte!").font(.subheadline).foregroundColor(.orange.opacity(0.8))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

struct WindowAccessor_System: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { if let window = view.window { context.coordinator.callback(window) } }; return view }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(callback: callback) }
    class Coordinator { let callback: (NSWindow) -> Void; init(callback: @escaping (NSWindow) -> Void) { self.callback = callback } }
}
class AnalysisWindowHandler: NSObject, NSWindowDelegate {
    let onCleanup: () -> Void; init(onCleanup: @escaping () -> Void) { self.onCleanup = onCleanup }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onCleanup(); return true }
}
