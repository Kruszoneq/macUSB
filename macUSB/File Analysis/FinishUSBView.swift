import SwiftUI
import AppKit

struct FinishUSBView: View {
    let systemName: String
    let mountPoint: URL
    let onReset: () -> Void
    let isPPC: Bool
    
    @State private var isCleaning: Bool = true
    @State private var cleanupSuccess: Bool = false
    @State private var cleanupErrorMessage: String? = nil
    
    var tempWorkURL: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_temp")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // CZĘŚĆ PRZEWIJANA (Informacje)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Zakończono")
                        .font(.title).bold()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 5)
                    
                    HStack(alignment: .center) {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green).frame(width: 32)
                        Text("Sukces!").font(.headline).foregroundColor(.green)
                        Spacer()
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1)).cornerRadius(8)
                    
                    HStack(alignment: .center) {
                        Image(systemName: "externaldrive.fill").font(.title2).foregroundColor(.blue).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Utworzono instalator systemu").font(.headline).foregroundColor(.blue)
                            // Nazwa systemu jest zmienną, więc wyświetlamy ją bez tłumaczenia (verbatim)
                            Text(verbatim: systemName).font(.headline).foregroundColor(.primary)
                        }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1)).cornerRadius(8)
                    
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle.fill").font(.title2).foregroundColor(.gray).frame(width: 32)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Co teraz?").font(.headline).foregroundColor(.primary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("• Podłącz dysk USB do docelowego komputera Mac")
                                
                                if isPPC {
                                    Spacer().frame(height: 8)
                                    Text("Intel:").bold()
                                    Text("• Uruchom komputer trzymając przycisk Option (⌥)")
                                    Text("• Wybierz instalator systemu macOS lub OS X z listy")
                                    
                                    Spacer().frame(height: 8)
                                    Text("PowerPC:").bold()
                                    Text("• Uruchom komputer w Open Firmware, trzymając klawisze Command (⌘) + Option (⌥) + O + F")
                                    Text("• Wpisz komendę bootowania z dysku USB adekwatną do twojego komputera")
                                    
                                    Spacer().frame(height: 8)
                                } else {
                                    Text("• Uruchom komputer trzymając przycisk Option (⌥)")
                                    Text("• Wybierz instalator systemu macOS lub OS X z listy")
                                }
                            }
                            .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1)).cornerRadius(8)
                    
                    if isPPC {
                        HStack(alignment: .center) {
                            Image(systemName: "info.circle.fill").font(.title2).foregroundColor(.gray).frame(width: 32)
                            Text("Szczegółowa instrukcja dostępna tutaj").font(.subheadline).foregroundColor(.secondary)
                            Spacer()
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
                            Text("Czyszczenie plików, proszę czekać...").font(.headline).foregroundColor(.blue)
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
                                    Text("Zakończono pracę!").font(.headline).foregroundColor(.green)
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
        .onAppear { performCleanupWithDelay() }
    }
    
    // --- LOGIKA ---
    func performCleanupWithDelay() {
        isCleaning = true
        let startTime = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            var success = true
            var errorMsg: String? = nil
            let unmountTask = Process(); unmountTask.launchPath = "/usr/bin/hdiutil"; unmountTask.arguments = ["detach", self.mountPoint.path, "-force"]; try? unmountTask.run(); unmountTask.waitUntilExit()
            if FileManager.default.fileExists(atPath: self.tempWorkURL.path) {
                do { try FileManager.default.removeItem(at: self.tempWorkURL) } catch {
                    success = false;
                    // ZMIANA: Użycie String(localized:) aby ten błąd dało się przetłumaczyć
                    errorMsg = String(localized: "Nie udało się usunąć plików tymczasowych: \(error.localizedDescription)")
                }
            }
            let elapsedTime = Date().timeIntervalSince(startTime); let minDuration: TimeInterval = 2.0
            if elapsedTime < minDuration { Thread.sleep(forTimeInterval: minDuration - elapsedTime) }
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.cleanupSuccess = success
                    self.cleanupErrorMessage = errorMsg
                    self.isCleaning = false
                }
            }
        }
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

