import SwiftUI
import AppKit

struct WelcomeView: View {
    
    // Odbieramy menedżera języka
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var dummyLock: Bool = false
    @State private var didRunStartupFlow: Bool = false
    
    let versionCheckURL = URL(string: "https://raw.githubusercontent.com/Kruszoneq/macUSB/main/version.json")!
    
    // Pusty inicjalizator (wymagany dla ContentView)
    init() {}

    private var visualMode: VisualSystemMode { currentVisualMode() }
    
    var body: some View {
        VStack(spacing: MacUSBDesignTokens.contentSectionSpacing) {
            
            Spacer()
            
            // --- LOGO I TYTUŁ ---
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            }

            Text("macUSB")
                .font(.system(size: 40 * MacUSBDesignTokens.headlineScale(for: visualMode), weight: .semibold))
            
            // Opis z obsługą tłumaczeń
            Text("Tworzenie bootowalnych dysków USB z systemem macOS oraz OS X nigdy nie było takie proste!")
                .font(.system(size: 17 * MacUSBDesignTokens.subheadlineScale(for: visualMode), weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.horizontal, 72)
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
            .macUSBPrimaryButtonStyle()
            
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
        .navigationTitle("Start")
        .onAppear {
            guard !didRunStartupFlow else { return }
            didRunStartupFlow = true
            checkForUpdates {
                HelperServiceManager.shared.bootstrapIfNeededAtStartup { _ in
                    NotificationPermissionManager.shared.handleStartupFlowIfNeeded()
                }
            }
        }
    }
    
    func checkForUpdates(completion: @escaping () -> Void) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        URLSession.shared.dataTask(with: versionCheckURL) { data, response, error in
            let finishOnMain: () -> Void = {
                DispatchQueue.main.async {
                    completion()
                }
            }

            guard let data = data, error == nil else {
                finishOnMain()
                return
            }
            
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
                            let remoteVersionLine = String(localized: "Dostępna jest nowa wersja: \(remoteVersion). Zalecamy aktualizację!")
                            let currentVersionLine = String(localized: "Aktualnie uruchomiona wersja: \(currentVersion)")
                            alert.informativeText = "\(remoteVersionLine)\n\(currentVersionLine)"
                            alert.addButton(withTitle: String(localized: "Pobierz"))
                            alert.addButton(withTitle: String(localized: "Ignoruj"))
                            let response = alert.runModal()
                            if response == .alertFirstButtonReturn, let url = URL(string: downloadLink) {
                                NSWorkspace.shared.open(url)
                            }
                            completion()
                        }
                    } else {
                        finishOnMain()
                    }
                } else {
                    finishOnMain()
                }
            } catch {
                print("Błąd sprawdzania aktualizacji: \(error)")
                finishOnMain()
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
