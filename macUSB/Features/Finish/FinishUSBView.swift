import SwiftUI
import AppKit
import UserNotifications

struct FinishUSBView: View {
    let systemName: String
    let mountPoint: URL
    let onReset: () -> Void
    let isPPC: Bool
    let didFail: Bool
    let didCancel: Bool
    let creationStartedAt: Date?
    let cleanupTempWorkURL: URL?
    let shouldDetachMountPoint: Bool
    let detectedSystemIcon: NSImage?
    
    @State private var isCleaning: Bool = true
    @State private var cleanupSuccess: Bool = false
    @State private var cleanupErrorMessage: String? = nil
    @State private var didPlayResultSound: Bool = false
    @State private var didSendBackgroundNotification: Bool = false
    @State private var completionDurationText: String? = nil

    init(
        systemName: String,
        mountPoint: URL,
        onReset: @escaping () -> Void,
        isPPC: Bool,
        didFail: Bool,
        didCancel: Bool = false,
        creationStartedAt: Date? = nil,
        cleanupTempWorkURL: URL? = nil,
        shouldDetachMountPoint: Bool = true,
        detectedSystemIcon: NSImage? = nil
    ) {
        self.systemName = systemName
        self.mountPoint = mountPoint
        self.onReset = onReset
        self.isPPC = isPPC
        self.didFail = didFail
        self.didCancel = didCancel
        self.creationStartedAt = creationStartedAt
        self.cleanupTempWorkURL = cleanupTempWorkURL
        self.shouldDetachMountPoint = shouldDetachMountPoint
        self.detectedSystemIcon = detectedSystemIcon
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
    private var sectionIconFont: Font { .title3 }
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
        if isCancelledResult { return String(localized: "Przerwano") }
        if isFailedResult { return String(localized: "Niepowodzenie!") }
        return String(localized: "Sukces!")
    }
    private var primaryResultSubtitle: String {
        if isCancelledResult { return String(localized: "Proces został zatrzymany przez użytkownika") }
        if isFailedResult { return String(localized: "Spróbuj ponownie od początku") }
        return String(localized: "Nośnik został przygotowany poprawnie")
    }
    private var summaryTitleText: String {
        if isCancelledResult { return String(localized: "Tworzenie nośnika zostało przerwane") }
        if isFailedResult { return String(localized: "Tworzenie instalatora nie powiodło się") }
        return String(localized: "Utworzono instalator systemu")
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
                                if isSuccessResult, let detectedSystemIcon {
                                    Image(nsImage: detectedSystemIcon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image(systemName: "externaldrive.fill")
                                        .font(sectionIconFont)
                                        .foregroundColor(primaryResultColor)
                                        .frame(width: MacUSBDesignTokens.iconColumnWidth)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(summaryTitleText).font(.headline).foregroundColor(primaryResultColor)
                                    Text(verbatim: systemName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                            }
                        }
                    }

                    if isSuccessResult {
                        StatusCard(tone: .neutral, density: .compact) {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Co teraz?").font(.headline).foregroundColor(.primary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("• Podłącz nośnik USB do docelowego komputera Mac")
                                        Text("• Uruchom komputer trzymając przycisk Option (⌥)")
                                        Text("• Wybierz instalator systemu macOS lub OS X z listy")
                                    }
                                    .font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    if isSuccessResult && isPPC && !isSnowLeopard {
                        StatusCard(tone: .subtle, density: .compact) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    Image(systemName: "globe.europe.africa.fill").font(sectionIconFont).foregroundColor(.secondary).frame(width: MacUSBDesignTokens.iconColumnWidth)
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("W przypadku Maca z PowerPC").font(.headline).foregroundColor(.primary)
                                        Text("Aby uruchomić instalator z nośnika USB na Macu z PowerPC, niezbędne jest wpisanie komendy w konsoli Open Firmware. Pełna instrukcja obsługi znajduje się na stronie internetowej aplikacji.")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        if let url = URL(string: "https://kruszoneq.github.io/macUSB/pages/guides/ppc_boot_instructions.html") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Text("Instrukcja bootowania z nośnika USB (GitHub)")
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
                                Text("Czyszczenie plików tymczasowych")
                                    .font(.headline)
                                    .bold()
                                    .foregroundColor(.accentColor)
                                Text("Proszę czekać")
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
                                        Text("Zakończono pracę!").font(.headline).foregroundColor(.green)
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
                                        Text("Błąd czyszczenia").font(.headline).foregroundColor(.red)
                                        if let msg = cleanupErrorMessage {
                                            Text(msg).font(.caption).foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }

                        Button(action: { onReset() }) {
                            HStack {
                                Text("Zacznij od początku")
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .macUSBSecondaryButtonStyle()

                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            HStack {
                                Text("Zakończ i wyjdź")
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
        .navigationTitle("Wynik operacji")
        .navigationBarBackButtonHidden(true)
        .background(
            WindowAccessor_Finish { window in
                window.styleMask.remove(.resizable)
            }
        )
        .onAppear {
            playResultSoundOnce()
            performCleanupWithDelay()
            sendSystemNotificationIfInactive()
        }
    }
    // --- LOGIKA ---
    func performCleanupWithDelay() {
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            var success = true
            var errorMsg: String? = nil
            if self.shouldDetachMountPoint {
                let unmountTask = Process()
                unmountTask.launchPath = "/usr/bin/hdiutil"
                unmountTask.arguments = ["detach", self.mountPoint.path, "-force"]
                try? unmountTask.run()
                unmountTask.waitUntilExit()
            }
            let tempCleanupNeeded = FileManager.default.fileExists(atPath: self.tempWorkURL.path)
            if tempCleanupNeeded {
                do {
                    try FileManager.default.removeItem(at: self.tempWorkURL)
                } catch {
                    let stillExists = FileManager.default.fileExists(atPath: self.tempWorkURL.path)
                    let nsError = error as NSError
                    let isNoSuchFile = nsError.domain == NSCocoaErrorDomain
                        && (nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError)

                    if !stillExists || isNoSuchFile {
                        AppLogging.info(
                            "FinishUSBView: cleanup fallback pominięty, pliki TEMP zostały już usunięte wcześniej.",
                            category: "Installation"
                        )
                    } else {
                        success = false
                        errorMsg = String(localized: "Nie udało się usunąć plików tymczasowych: \(error.localizedDescription)")
                    }
                }
            } else {
                AppLogging.info(
                    "FinishUSBView: pomijam fallback cleanup TEMP, helper usunął pliki wcześniej.",
                    category: "Installation"
                )
            }
            
            DispatchQueue.main.async {
                let durationMetrics = self.currentCompletionDuration()
                let durationText = self.makeCompletionDurationText(durationMetrics)
                let resultState = self.didCancel ? "PRZERWANO" : (self.didFail ? "NIEPOWODZENIE" : "SUKCES")
                if let durationMetrics {
                    AppLogging.info(
                        "Czas procesu USB: \(durationMetrics.displayText) (\(durationMetrics.totalSeconds)s), wynik: \(resultState).",
                        category: "Installation"
                    )
                } else {
                    AppLogging.info(
                        "Czas procesu USB: brak danych startu, wynik: \(resultState).",
                        category: "Installation"
                    )
                }

                withAnimation(.easeInOut(duration: 0.5)) {
                    self.cleanupSuccess = success
                    self.cleanupErrorMessage = errorMsg
                    self.completionDurationText = durationText
                    self.isCleaning = false
                }
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
            format: String(localized: "Ukończono w %02dm %02ds"),
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

        let title = isFailedResult ? String(localized: "Wystąpił błąd") : String(localized: "Instalator gotowy")
        let body = isFailedResult
            ? String(localized: "Proces tworzenia instalatora na wybranym nośniku zakończył się niepowodzeniem.")
            : String(localized: "Proces zapisu na nośniku zakończył się pomyślnie.")

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
