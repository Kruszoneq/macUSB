import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}

@main
struct macUSBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // --- LOGIKA JĘZYKOWA (Hard Force English Fallback) ---
        
        // 1. Pobieramy preferowane języki użytkownika z systemu
        let userLanguages = Locale.preferredLanguages // np. ["it-IT", "en-US"]
        
        // 2. Definiujemy, co my wspieramy (bez "Base")
        // UWAGA: Nie wpisujemy tu "pl", jeśli chcemy, by PL działało tylko dla PL,
        // a dla reszty EN. Ale dla bezpieczeństwa dajemy oba.
        let supportedLanguages = ["pl", "de", "fr", "es", "pt", "ja", "zh", "ru", "en"]
        
        // 3. Sprawdzamy, czy pierwszy preferowany język użytkownika jest u nas wspierany
        let primaryUserLang = userLanguages.first?.prefix(2).lowercased() ?? "en" // np. "it"
        
        let isSupported = supportedLanguages.contains(String(primaryUserLang))
        
        // 4. KLUCZOWY MOMENT:
        // Jeśli język to np. IT (niewspierany), a my mamy kod w PL (Base),
        // to system weźmie PL. Musimy temu zapobiec i wymusić EN.
        
        if !isSupported {
            // Wymuszamy Angielski dla wszystkich niewspieranych
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize() // Ważne: zapisz natychmiast
        } else {
            // Jeśli język jest wspierany (np. PL, DE), usuwamy wymuszenie,
            // żeby system sam wybrał właściwy plik .strings
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
        
        // --- KONIEC LOGIKI JĘZYKOWEJ ---

        // Blokada przed podwójnym uruchomieniem
        if let bundleId = Bundle.main.bundleIdentifier {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if runningApps.count > 1 {
                for app in runningApps where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 550, height: 750)
                .frame(minWidth: 550, maxWidth: 550, minHeight: 750, maxHeight: 750)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .windowList) { }
        }
    }
}
