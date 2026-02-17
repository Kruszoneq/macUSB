import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct SystemAnalysisView: View {
    
    @Binding var isTabLocked: Bool
    @StateObject private var logic = AnalysisLogic()
    @State private var shouldResetToStart: Bool = false
    
    @State private var selectedDriveDisplayNameSnapshot: String? = nil
    @State private var selectedDriveForInstallationSnapshot: USBDrive? = nil
    @State private var navigateToInstall: Bool = false
    @State private var isDragTargeted: Bool = false
    @State private var analysisWindowHandler: AnalysisWindowHandler?
    @State private var hostingWindow: NSWindow? = nil
    
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
        let isValidSelection = (logic.sourceAppURL != nil) || logic.isPPC || logic.isMavericks

        let unrecognizedBlocking = (!logic.isSystemDetected
                                    && !logic.recognizedVersion.isEmpty
                                    && logic.sourceAppURL == nil
                                    && !logic.showUnsupportedMessage)

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
    
    // MARK: - Subviews split to help the type-checker
    private var headerSection: some View {
        EmptyView()
    }

    private var fileRequirementsBox: some View {
        StatusCard(tone: .neutral, density: .compact) {
            HStack(alignment: .top) {
                Image(systemName: "info.circle.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Wymagania").font(.headline).foregroundColor(.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("• Wybrany plik musi zawierać instalator systemu macOS lub Mac OS X")
                        Text("• Dozwolone formaty plików to .dmg, .iso, .cdr oraz .app")
                        Text("• Wymagane jest co najmniej 15 GB wolnego miejsca na dysku twardym")
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
        let isValid = (logic.sourceAppURL != nil) || logic.isPPC
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
            if let appURL = logic.sourceAppURL {
                NavigationLink(
                    destination: UniversalInstallationView(
                        sourceAppURL: appURL,
                        targetDrive: selectedDriveForInstallationSnapshot,
                        targetDriveDisplayName: selectedDriveDisplayNameSnapshot,
                        systemName: logic.recognizedVersion,
                        detectedSystemIcon: logic.detectedSystemIcon,
                        originalImageURL: logic.selectedFileUrl,
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
        ((logic.sourceAppURL != nil) || logic.isPPC) && (logic.isSystemDetected || logic.isPPC || logic.isMavericks)
    }

    private var canProceedToInstall: Bool {
        canUseUSBSelection && logic.selectedDrive != nil && logic.capacityCheckFinished && logic.isCapacitySufficient
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: MacUSBDesignTokens.contentSectionSpacing) {
                        headerSection
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
                            .disabled(!canUseUSBSelection)
                            .opacity(canUseUSBSelection ? 1.0 : 0.5)
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
            MenuState.shared.skipAnalysisEnabled = false
        }
        .onChange(of: logic.showUnsupportedMessage) { _ in updateMenuState() }
        .onChange(of: logic.recognizedVersion) { _ in updateMenuState() }
        .onChange(of: logic.isAnalyzing) { _ in updateMenuState() }
        .onChange(of: logic.isSystemDetected) { _ in updateMenuState() }
        .onChange(of: logic.selectedFilePath) { _ in updateMenuState() }
        .onChange(of: logic.isPPC) { _ in updateMenuState() }
        .onChange(of: logic.sourceAppURL) { _ in updateMenuState() }
        .onChange(of: logic.shouldShowMavericksDialog) { show in
            if show { presentMavericksDialog() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macUSBStartTigerMultiDVD)) { _ in
            logic.forceTigerMultiDVDSelection()
        }
        .onAppear {
            logic.refreshDrives()
            updateMenuState()
            if logic.shouldShowMavericksDialog { presentMavericksDialog() }
        }
        .navigationTitle("Konfiguracja źródła i celu")
        .navigationBarBackButtonHidden(true)
    }
    
    var usbSelectionSection: some View {
        VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
            sectionDivider("Wybór nośnika USB")
            StatusCard(tone: .neutral, density: .compact) {
                HStack(alignment: .top) {
                    Image(systemName: "externaldrive.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Wymagania sprzętowe").font(.headline)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("• Do utworzenia instalatora potrzebny jest nośnik USB o pojemności minimum 16 GB").font(.subheadline).foregroundColor(.secondary)
                            Text("• Zalecane jest użycie dysku w standardzie USB 3.0 lub szybszym").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Wybierz docelowy nośnik USB:").font(.subheadline)
                if logic.availableDrives.isEmpty {
                    StatusCard(tone: .error, density: .compact) {
                        HStack {
                            Image(systemName: "externaldrive.badge.xmark").font(sectionIconFont).foregroundColor(.red).frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading) {
                                Text("Nie wykryto nośnika USB").font(.headline).foregroundColor(.red)
                                Text("Podłącz nośnik USB i poczekaj na wykrycie...").font(.caption).foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                } else {
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
            .onChange(of: logic.selectedDrive) { _ in logic.checkCapacity() }
            
            if logic.selectedDrive != nil {
                if logic.capacityCheckFinished && !logic.isCapacitySufficient {
                    StatusCard(tone: .error, density: .compact) {
                        HStack {
                            Image(systemName: "xmark.circle.fill").font(sectionIconFont).foregroundColor(.red).frame(width: MacUSBDesignTokens.iconColumnWidth)
                            VStack(alignment: .leading) {
                                Text("Wybrany nośnik USB ma za małą pojemność").font(.headline).foregroundColor(.red)
                                Text("Wymagane jest minimum 16 GB.").font(.caption).foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                    .transition(.opacity)
                }
                if logic.capacityCheckFinished && logic.isCapacitySufficient {
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
