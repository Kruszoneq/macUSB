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

    @State var errorMessage: String = ""
    @State var isHelperWorking: Bool = false
    @State var helperProgressPercent: Double = 0
    @State var helperStageTitleKey: String = ""
    @State var helperStatusKey: String = ""
    @State var helperCurrentStageKey: String = ""
    @State var helperWriteSpeedText: String = "- MB/s"
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
    
    @State var isCancelling: Bool = false
    @State var usbProcessStartedAt: Date?
    
    @State var windowHandler: UniversalWindowHandler?
    
    var tempWorkURL: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_temp")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // CZĘŚĆ PRZEWIJANA
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Szczegóły operacji")
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
                                Text("Wybrany nośnik USB").font(.caption).foregroundColor(.secondary)
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
                                    Text("• Obraz z systemem zostanie skopiowany i zweryfikowany")
                                    Text("• Nośnik USB zostanie sformatowany")
                                    Text("• Obraz systemu zostanie przywrócony")
                                } else if isPPC {
                                    Text("• Nośnik USB zostanie odpowiednio sformatowany")
                                    Text("• Obraz instalacyjny zostanie przywrócony")
                                } else {
                                    Text("• Pliki systemowe zostaną przygotowane")
                                    Text("• Nośnik USB zostanie sformatowany")
                                    Text("• Pliki instalacyjne zostaną skopiowane")
                                    if isCatalina {
                                        Text("• Struktura instalatora zostanie sfinalizowana")
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
                    
                    if !isProcessing && !isHelperWorking && !isCancelled && !isUSBDisconnectedLock && !isCancelling {
                        VStack(spacing: 15) {
                            Button(action: showStartCreationAlert) {
                                HStack {
                                    Text("Rozpocznij")
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                                .frame(maxWidth: .infinity).padding(8)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.accentColor)
                            
                            Button(action: returnToAnalysisViewPreservingSelection) {
                                HStack {
                                    Text("Wróć")
                                    Image(systemName: "arrow.left.circle")
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
                                Text("Odłączono nośnik USB")
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
                            return self.isCancelled
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
                destination: CreationProgressView(
                    systemName: systemName,
                    mountPoint: sourceAppURL.deletingLastPathComponent(),
                    detectedSystemIcon: detectedSystemIcon,
                    isCatalina: isCatalina,
                    isRestoreLegacy: isRestoreLegacy,
                    isMavericks: isMavericks,
                    isPPC: isPPC,
                    needsPreformat: (targetDrive?.needsFormatting ?? false) && !isPPC,
                    onReset: {
                        NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                        self.isTabLocked = false
                        self.rootIsActive = false
                    },
                    onCancelRequested: showCreationProgressCancelAlert,
                    canCancelWorkflow: !didCancelCreation && !navigateToFinish,
                    helperStageTitleKey: $helperStageTitleKey,
                    helperStatusKey: $helperStatusKey,
                    helperCurrentStageKey: $helperCurrentStageKey,
                    helperWriteSpeedText: $helperWriteSpeedText,
                    isHelperWorking: $isHelperWorking,
                    isCancelling: $isCancelling,
                    navigateToFinish: $navigateToFinish,
                    helperOperationFailed: $helperOperationFailed,
                    didCancelCreation: $didCancelCreation,
                    creationStartedAt: $usbProcessStartedAt
                ),
                isActive: $navigateToCreationProgress
            ) { EmptyView() }
            .hidden()
        )
        .onAppear {
            AppLogging.separator()
            AppLogging.separator()
            AppLogging.info("Przejście do kreatora", category: "Navigation")
            AppLogging.separator()
            AppLogging.separator()
            if !isProcessing && !isHelperWorking && !isCancelled && !isUSBDisconnectedLock && !navigateToCreationProgress {
                startUSBMonitoring()
            }
        }
        .onDisappear {
            stopUSBMonitoring()
            if !navigateToCreationProgress && !isHelperWorking {
                stopHelperWriteSpeedMonitoring()
            }
        }
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
