import SwiftUI
import AppKit

struct UniversalInstallationView: View {
    let sourceAppURL: URL
    let targetDrive: USBDrive?
    let targetDriveDisplayName: String?
    let systemName: String
    let detectedSystemIcon: NSImage?
    let originalImageURL: URL?
    
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
    
    // NOWE STANY UI DLA AUTH
    @State var showAuthWarning: Bool = false
    @State var isRollingBack: Bool = false
    
    @State var errorMessage: String = ""
    @State var isTerminalWorking: Bool = false
    @State var helperProgressPercent: Double = 0
    @State var helperStageTitle: String = ""
    @State var helperStatusText: String = ""
    @State var activeHelperWorkflowID: String? = nil
    @State var showFinishButton: Bool = false
    @State var processSuccess: Bool = false
    @State var navigateToFinish: Bool = false
    @State var isCancelled: Bool = false
    @State var isUSBDisconnectedLock: Bool = false
    @State var usbCheckTimer: Timer?
    
    // New terminal failure state
    @State var terminalFailed: Bool = false
    
    // Stan rozruchowy dla monitoringu
    @State var monitoringWarmupCounter: Int = 0
    @State var isCancelling: Bool = false
    
    @State var windowHandler: UniversalWindowHandler?
    
    var tempWorkURL: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_temp")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // CZĘŚĆ PRZEWIJANA
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Kreator instalatora macOS")
                        .font(.title).bold()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 5)
                    
                    // RAMKA: System Info
                    HStack {
                        if let detectedSystemIcon {
                            Image(nsImage: detectedSystemIcon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "applelogo")
                                .font(.title2)
                                .foregroundColor(.green)
                                .frame(width: 32)
                        }
                        VStack(alignment: .leading) {
                            Text("Wybrana wersja systemu").font(.caption).foregroundColor(.secondary)
                            Text(systemName).font(.headline).foregroundColor(.green).bold()
                        }
                        Spacer()
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1)).cornerRadius(8)
                    
                    // RAMKA: Dysk USB
                    if let name = targetDriveDisplayName ?? targetDrive?.displayName {
                        HStack {
                            Image(systemName: "externaldrive.fill").font(.title2).foregroundColor(.blue).frame(width: 32)
                            VStack(alignment: .leading) {
                                Text("Wybrany dysk USB").font(.caption).foregroundColor(.secondary)
                                Text(name).font(.headline)
                            }
                            Spacer()
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1)).cornerRadius(8)
                    }

                    if let drive = targetDrive, drive.usbSpeed == .usb2 {
                        HStack(alignment: .center) {
                            Image(systemName: "externaldrive.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wybrano nośnik USB 2.0")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text("Wybrany nośnik pracuje w starszym standardzie przesyłu danych. Proces tworzenia instalatora może potrwać kilkanaście minut")
                                    .font(.subheadline)
                                    .foregroundColor(.orange.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity)
                    }
                    
                    // RAMKA: Przebieg
                    HStack(alignment: .top) {
                        Image(systemName: "gearshape.2").font(.title2).foregroundColor(.secondary).frame(width: 32)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Przebieg procesu").font(.headline)
                            VStack(alignment: .leading, spacing: 5) {
                                if isRestoreLegacy {
                                    Text("• Plik z systemem zostanie skopiowany i zweryfikowany")
                                    Text("• Pamięć USB zostanie wymazana")
                                    Text("• Obraz systemu zostanie przywrócony przez helper systemowy")
                                    Text("• System może poprosić o potwierdzenie uprawnień administratora")
                                } else if isPPC {
                                    Text("• Dysk USB zostanie sformatowany (APM + HFS+)")
                                    Text("• Obraz instalacyjny zostanie przywrócony na USB")
                                    Text("• Operacja zostanie wykonana przez helper systemowy (wymagane uprawnienia administratora)")
                                } else {
                                    if isCatalina {
                                        Text("• Plik instalacyjny zostanie skopiowany oraz podpisany")
                                    } else {
                                        Text("• Plik instalacyjny zostanie skopiowany")
                                        if needsCodesign {
                                            Text("• Instalator zostanie zmodyfikowany (podpis cyfrowy)")
                                        }
                                    }
                                    
                                    Text("• Pamięć USB zostanie sformatowana (dane zostaną usunięte)")
                                    Text("• Zapis na USB zostanie wykonany przez helper systemowy")
                                    if isCatalina {
                                        Text("• Helper wykona końcową weryfikację i podmianę plików")
                                    }
                                }
                                Text("• Pliki tymczasowe zostaną automatycznie usunięte")
                            }
                            .font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1)).cornerRadius(8)
                    
                    // RAMKA: Czas trwania
                    HStack(alignment: .center, spacing: 15) {
                        Image(systemName: "clock").font(.title2).foregroundColor(.secondary).frame(width: 32)
                        Text("Cały proces może potrwać kilka minut.").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1)).cornerRadius(8)
                    
                    // RAMKA: Globalny Błąd
                    if !errorMessage.isEmpty {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wystąpił błąd")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.scale)
                    }
                }
                .padding()
            }
            
            // STICKY FOOTER
            VStack(spacing: 0) {
                Divider()
                
                VStack(spacing: 15) {
                    
                    if !isProcessing && !isTerminalWorking && !processSuccess && !isCancelled && !isUSBDisconnectedLock && !isRollingBack && !isCancelling {
                        VStack(spacing: 15) {
                            Button(action: startCreationProcessEntry) {
                                HStack {
                                    Text("Rozpocznij")
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                                .frame(maxWidth: .infinity).padding(8)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.accentColor)
                            
                            Button(action: showCancelAlert) {
                                HStack {
                                    Text("Przerwij i zakończ")
                                    Image(systemName: "xmark.circle")
                                }
                                .frame(maxWidth: .infinity).padding(8)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.gray.opacity(0.2))
                        }
                        .transition(.opacity)
                    }
                    
                    if isCancelling {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Przerywanie działania")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text("Proszę czekać...")
                                    .font(.caption)
                                    .foregroundColor(.orange.opacity(0.8))
                            }
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity)
                    }
                    
                    // RAMKA: Anulowano przez użytkownika
                    if isCancelled {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Proces przerwany")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text("Działanie przerwane przez użytkownika. Możesz zacząć od początku.")
                                    .font(.caption)
                                    .foregroundColor(.orange.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity)
                        
                        Button(action: {
                            NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                            self.isTabLocked = false
                            self.rootIsActive = false
                        }) {
                            HStack {
                                Text("Zacznij od początku")
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Color.gray.opacity(0.2))
                    }
                    
                    // RAMKA: Odłączono USB
                    if isUSBDisconnectedLock {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Odłączono dysk USB")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text("Dalsze działanie aplikacji zostało zablokowane. Aby zacząć od nowa, uruchom ponownie aplikację.")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity)
                        
                        Button(action: {
                            NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                            self.isTabLocked = false
                            self.rootIsActive = false
                        }) {
                            HStack {
                                Text("Zacznij od początku")
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Color.gray.opacity(0.2))
                    }
                    
                    // STATUS: Przetwarzanie / Ostrzeżenia
                    if isProcessing || isRollingBack {
                        VStack(spacing: 20) {
                            HStack(spacing: 15) {
                                if isRollingBack {
                                    Image(systemName: "xmark.octagon.fill").font(.largeTitle).foregroundColor(.red)
                                } else {
                                    Image(systemName: processingIcon).font(.largeTitle).foregroundColor(.accentColor)
                                }
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(processingTitle.isEmpty ? String(localized: "Rozpoczynanie...") : processingTitle)
                                        .font(.headline)
                                    Text(processingSubtitle.isEmpty ? String(localized: "Przygotowywanie operacji...") : processingSubtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            
                            // RAMKA: Autoryzacja
                            if showAuthWarning {
                                HStack(alignment: .center) {
                                    Image(systemName: "lock.fill")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Wymagana autoryzacja")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                        Text("Wprowadź hasło administratora, aby kontynuować.")
                                            .font(.caption)
                                            .foregroundColor(.orange.opacity(0.8))
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                .transition(.scale)
                            }
                            
                            // RAMKA: Brak autoryzacji / Rollback
                            if isRollingBack {
                                HStack(alignment: .center) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Brak autoryzacji")
                                            .font(.headline)
                                            .foregroundColor(.red)
                                        Text("Operacja została anulowana przez użytkownika.")
                                            .font(.caption)
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .transition(.scale)
                            }
                            
                            Divider()
                            
                            if !isRollingBack {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Proces w toku...").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isRollingBack ? Color.red.opacity(0.05) : Color.accentColor.opacity(0.1))
                        .cornerRadius(10)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    if isTerminalWorking {
                        VStack(spacing: 20) {
                            HStack(spacing: 15) {
                                Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(helperStageTitle.isEmpty ? String(localized: "Rozpoczynanie...") : helperStageTitle)
                                        .font(.headline)
                                    Text(helperStatusText.isEmpty ? String(localized: "Nawiązywanie połączenia XPC...") : helperStatusText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(Int(helperProgressPercent))%")
                                    .font(.headline)
                            }
                            Divider()
                            ProgressView(value: helperProgressPercent, total: 100)
                                .progressViewStyle(.linear)
                        }
                        .padding().frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.1)).cornerRadius(10)
                        .transition(.opacity)
                    }
                    
                    if processSuccess {
                         VStack(spacing: 20) {
                             HStack(spacing: 15) {
                                 Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundColor(.green)
                                 VStack(alignment: .leading, spacing: 5) {
                                     Text("Gotowe!").font(.headline)
                                     Text("Przejdź dalej, aby zakończyć proces...").font(.caption).foregroundColor(.secondary)
                                 }
                                 Spacer()
                             }
                             Divider()
                             VStack(spacing: 10) {
                                 Button(action: { navigateToFinish = true }) {
                                     HStack {
                                         Text("Zakończ")
                                         Image(systemName: "arrow.right.circle.fill")
                                     }
                                     .frame(maxWidth: .infinity).padding(5)
                                 }
                                 .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.green)
                             }
                         }
                         .padding().frame(maxWidth: .infinity)
                         .background(Color.green.opacity(0.1)).cornerRadius(10)
                         .transition(.opacity)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: 550, height: 750)
        .navigationTitle("macUSB")
        .navigationBarBackButtonHidden(isTabLocked)
        .background(
            WindowAccessor_Universal { window in
                window.styleMask.remove(NSWindow.StyleMask.resizable)
                
                if self.windowHandler == nil {
                    let handler = UniversalWindowHandler(
                        shouldClose: {
                            return self.showFinishButton || self.isCancelled || self.processSuccess
                        },
                        onCleanup: {
                            self.performEmergencyCleanup(mountPoint: sourceAppURL.deletingLastPathComponent(), tempURL: tempWorkURL)
                        }
                    )
                    window.delegate = handler
                    self.windowHandler = handler
                }
            }
        )
        .background(
            NavigationLink(
                destination: FinishUSBView(
                    systemName: systemName,
                    mountPoint: sourceAppURL.deletingLastPathComponent(),
                    onReset: {
                        // Post reset signal and pop to the beginning
                        NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                        // Unlock and navigate back to root
                        self.isTabLocked = false
                        self.rootIsActive = false
                    },
                    isPPC: isPPC,
                    didFail: terminalFailed
                ),
                isActive: $navigateToFinish
            ) { EmptyView() }
            .hidden()
        )
        .onAppear {
            AppLogging.separator()
            AppLogging.separator()
            AppLogging.info("Przejście do kreatora", category: "Navigation")
            AppLogging.separator()
            AppLogging.separator()
            if !isProcessing && !isTerminalWorking && !processSuccess && !isCancelled && !isUSBDisconnectedLock && !isRollingBack {
                startUSBMonitoring()
            }
        }
        .onDisappear { stopUSBMonitoring() }
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

class UniversalWindowHandler: NSObject, NSWindowDelegate {
    let shouldClose: () -> Bool
    let onCleanup: () -> Void
    init(shouldClose: @escaping () -> Bool, onCleanup: @escaping () -> Void) {
        self.shouldClose = shouldClose
        self.onCleanup = onCleanup
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if shouldClose() {
            onCleanup()
            return true
        }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "UWAGA!")
        alert.informativeText = String(localized: "Czy na pewno chcesz przerwać pracę?")
        alert.addButton(withTitle: String(localized: "Nie"))
        alert.addButton(withTitle: String(localized: "Tak"))
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            onCleanup()
            NSApplication.shared.terminate(nil)
            return true
        } else { return false }
    }
}
