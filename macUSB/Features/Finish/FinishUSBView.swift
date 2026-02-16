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
        shouldDetachMountPoint: Bool = true
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
    
    var body: some View {
        VStack(spacing: 0) {
            
            // CZĘŚĆ PRZEWIJANA (Informacje)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Wynik operacji")
                        .font(.title).bold()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 5)
                    
                    if isCancelledResult {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill").font(.title2).foregroundColor(.red).frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Przerwano").font(.headline).foregroundColor(.red)
                                Text("Proces został zatrzymany przez użytkownika").font(.caption).foregroundColor(.red)
                            }
                            Spacer()
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1)).cornerRadius(8)
                    } else if isFailedResult {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill").font(.title2).foregroundColor(.red).frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Niepowodzenie!").font(.headline).foregroundColor(.red)
                                Text("Spróbuj ponownie od początku").font(.caption).foregroundColor(.red)
                            }
                            Spacer()
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1)).cornerRadius(8)
                    } else {
                        HStack(alignment: .center) {
                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green).frame(width: 32)
                            Text("Sukces!").font(.headline).foregroundColor(.green)
                            Spacer()
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1)).cornerRadius(8)
                    }
                    
                    HStack(alignment: .center) {
                        Image(systemName: "externaldrive.fill").font(.title2).foregroundColor((isFailedResult || isCancelledResult) ? .red : .blue).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            if isCancelledResult {
                                Text("Tworzenie nośnika zostało przerwane").font(.headline).foregroundColor(.red)
                                Text(verbatim: systemName).font(.headline).foregroundColor(.primary)
                            } else if isFailedResult {
                                Text("Tworzenie instalatora nie powiodło się").font(.headline).foregroundColor(.red)
                                Text(verbatim: systemName).font(.headline).foregroundColor(.primary)
                            } else {
                                Text("Utworzono instalator systemu").font(.headline).foregroundColor(.blue)
                                Text(verbatim: systemName).font(.headline).foregroundColor(.primary)
                            }
                        }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(((isFailedResult || isCancelledResult) ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))).cornerRadius(8)
                    
                    if isSuccessResult {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle.fill").font(.title2).foregroundColor(.gray).frame(width: 32)
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
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1)).cornerRadius(8)
                    }
                    
                    if isSuccessResult && isPPC && !isSnowLeopard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Image(systemName: "globe.europe.africa.fill").font(.title2).foregroundColor(.gray).frame(width: 32)
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
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1)).cornerRadius(8)
                    }
                    
                }
                .padding()
            }
            
            // STICKY FOOTER (Czyszczenie i Wyjście)
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 15) {
                    if isCleaning {
                        HStack(alignment: .center) {
                            Image(systemName: "trash.fill").font(.title2).foregroundColor(.blue).frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Czyszczenie plików tymczasowych")
                                    .font(.headline)
                                    .bold()
                                    .foregroundColor(.blue)
                                Text("Proszę czekać")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1)).cornerRadius(8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        // Grupa wyników i przycisku
                        VStack(spacing: 15) {
                            if cleanupSuccess {
                                HStack(alignment: .center) {
                                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Zakończono pracę!").font(.headline).foregroundColor(.green)
                                        if let completionDurationText {
                                            Text(completionDurationText)
                                                .font(.subheadline)
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.1)).cornerRadius(8)
                            } else {
                                HStack(alignment: .top) {
                                    Image(systemName: "xmark.octagon.fill").font(.title2).foregroundColor(.red).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Błąd czyszczenia").font(.headline).foregroundColor(.red)
                                        if let msg = cleanupErrorMessage {
                                            // Tutaj msg jest już zlokalizowane (pochodzi z catch)
                                            Text(msg).font(.caption).foregroundColor(.red)
                                        }
                                    }
                                }
                                .padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1)).cornerRadius(8)
                            }
                            
                            Button(action: { onReset() }) {
                                HStack {
                                    Text("Zacznij od początku")
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .frame(maxWidth: .infinity).padding(8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(Color.gray.opacity(0.2))
                            
                            Button(action: { NSApplication.shared.terminate(nil) }) {
                                HStack {
                                    Text("Zakończ i wyjdź")
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .frame(maxWidth: .infinity).padding(8)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large).tint(.accentColor)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        // ZMIANA: Sztywny rozmiar
        .frame(width: 550, height: 750)
        .navigationTitle("macUSB")
        .navigationBarBackButtonHidden(true)
        // ZMIANA: Blokada zmiany rozmiaru po załadowaniu okna
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
                do { try FileManager.default.removeItem(at: self.tempWorkURL) } catch {
                    success = false;
                    // ZMIANA: Użycie String(localized:) aby ten błąd dało się przetłumaczyć
                    errorMsg = String(localized: "Nie udało się usunąć plików tymczasowych: \(error.localizedDescription)")
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
