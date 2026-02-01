import SwiftUI
import AppKit

struct WelcomeView: View {
    
    // Odbieramy menedżera języka
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var dummyLock: Bool = false
    
    let versionCheckURL = URL(string: "https://raw.githubusercontent.com/Kruszoneq/macUSB/main/version.json")!
    
    // Pusty inicjalizator (wymagany dla ContentView)
    init() {}
    
    var body: some View {
        VStack(spacing: 20) {
            
            Spacer()
            
            // --- LOGO I TYTUŁ ---
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            }
            
            Text("macUSB")
                .font(.system(size: 40, weight: .bold))
            
            // Opis z obsługą tłumaczeń
            Text("Tworzenie bootowalnych dysków USB z systemem macOS\noraz OS X nigdy nie było takie proste!")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            // --- PRZYCISK START ---
            NavigationLink(destination: SystemAnalysisView(isTabLocked: $dummyLock)) {
                HStack {
                    Text("Rozpocznij") // Klucz do tłumaczenia
                        .font(.headline)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 30)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.accentColor)
            
            Spacer()
            
            // --- STOPKA (Bottom Bar) ---
            HStack {
                Spacer()
                Text("macUSB by Kruszoneq")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 25)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkForUpdates()
        }
    }
    
    func checkForUpdates() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        URLSession.shared.dataTask(with: versionCheckURL) { data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
                   let remoteVersion = json["version"],
                   let downloadLink = json["url"] {
                    
                    if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.icon = NSApplication.shared.applicationIconImage
                            alert.alertStyle = .informational
                            alert.messageText = String(localized: "Dostępna aktualizacja!")
                            alert.informativeText = String(localized: "Dostępna jest nowa wersja: \(remoteVersion). Zalecamy aktualizację!")
                            alert.addButton(withTitle: String(localized: "Pobierz"))
                            alert.addButton(withTitle: String(localized: "Ignoruj"))
                            let response = alert.runModal()
                            if response == .alertFirstButtonReturn, let url = URL(string: downloadLink) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } catch {
                print("Błąd sprawdzania aktualizacji: \(error)")
            }
        }.resume()
    }
    
    private func restartApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

