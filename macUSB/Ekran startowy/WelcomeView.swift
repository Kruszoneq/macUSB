import SwiftUI
import AppKit

struct WelcomeView: View {
    
    // Odbieramy menedżera języka
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var dummyLock: Bool = false
    @State private var showUpdateAlert: Bool = false
    @State private var updateVersion: String = ""
    @State private var updateURL: String = ""
    
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
                // LEWA STRONA: Autor
                Text("macUSB by Kruszoneq")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
                
                Spacer()
                
                // PRAWA STRONA: Wybór języka
                Menu {
                    // Sekcja: Wybierz język
                    // 🇵🇱 Polish
                    Button { languageManager.currentLanguage = "pl" } label: {
                        Label("Polski 🇵🇱", systemImage: languageManager.currentLanguage == "pl" ? "checkmark" : "")
                    }
                    
                    // 🇺🇸 English
                    Button { languageManager.currentLanguage = "en" } label: {
                        Label("English 🇺🇸", systemImage: languageManager.currentLanguage == "en" ? "checkmark" : "")
                    }
                    
                    // 🇩🇪 German
                    Button { languageManager.currentLanguage = "de" } label: {
                        Label("Deutsch 🇩🇪", systemImage: languageManager.currentLanguage == "de" ? "checkmark" : "")
                    }
                    
                    // 🇫🇷 French
                    Button { languageManager.currentLanguage = "fr" } label: {
                        Label("Français 🇫🇷", systemImage: languageManager.currentLanguage == "fr" ? "checkmark" : "")
                    }
                    
                    // 🇪🇸 Spanish
                    Button { languageManager.currentLanguage = "es" } label: {
                        Label("Español 🇪🇸", systemImage: languageManager.currentLanguage == "es" ? "checkmark" : "")
                    }
                    
                    // 🇧🇷 Portuguese (Brazil)
                    Button { languageManager.currentLanguage = "pt-BR" } label: {
                        Label("Português (BR) 🇧🇷", systemImage: languageManager.currentLanguage == "pt-BR" ? "checkmark" : "")
                    }
                    
                    // 🇷🇺 Russian
                    Button { languageManager.currentLanguage = "ru" } label: {
                        Label("Русский 🇷🇺", systemImage: languageManager.currentLanguage == "ru" ? "checkmark" : "")
                    }
                    
                    // 🇨🇳 Simplified Chinese
                    Button { languageManager.currentLanguage = "zh-Hans" } label: {
                        Label("简体中文 🇨🇳", systemImage: languageManager.currentLanguage == "zh-Hans" ? "checkmark" : "")
                    }
                    
                    // 🇯🇵 Japanese
                    Button { languageManager.currentLanguage = "ja" } label: {
                        Label("日本語 🇯🇵", systemImage: languageManager.currentLanguage == "ja" ? "checkmark" : "")
                    }
                    
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text("Zmień język") // Klucz do tłumaczenia (np. "Change Language")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize() // Zapobiega ucinaniu tekstu
            }
            .padding(.horizontal, 25)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkForUpdates()
        }
        .alert("Dostępna aktualizacja", isPresented: $showUpdateAlert) {
            Button("Pobierz", role: .none) {
                if let url = URL(string: updateURL) { NSWorkspace.shared.open(url) }
            }
            Button("Ignoruj", role: .cancel) { }
        } message: {
            Text("Dostępna jest wersja \(updateVersion). Zalecamy aktualizację.")
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
                            self.updateVersion = remoteVersion
                            self.updateURL = downloadLink
                            self.showUpdateAlert = true
                        }
                    }
                }
            } catch {
                print("Błąd sprawdzania aktualizacji: \(error)")
            }
        }.resume()
    }
}
