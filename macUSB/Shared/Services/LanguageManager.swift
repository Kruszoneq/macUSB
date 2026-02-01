import SwiftUI
import Combine

class LanguageManager: ObservableObject {
    
    // Lista kodów wspieranych przez aplikację (używana globalnie)
    static let supportedLanguages: [String] = [
        "pl",       // Polski
        "en",       // Angielski
        "de",       // Niemiecki
        "ja",       // Japoński
        "fr",       // Francuski
        "es",       // Hiszpański
        "pt-BR",    // Portugalski (Brazylia)
        "zh-Hans",  // Chiński Uproszczony
        "ru"        // Rosyjski
    ]

    // Sprawdza, czy dany identyfikator jest wspierany (dokładnie lub po prefiksie języka)
    static func isLanguageSupported(_ identifier: String) -> Bool {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        if supportedLanguages.contains(normalized) { return true }
        let code = normalized.components(separatedBy: "-").first ?? normalized
        if supportedLanguages.contains(code) { return true }
        return supportedLanguages.contains { normalized.hasPrefix($0) }
    }

    // Wywoływana jak najwcześniej przy starcie aplikacji, aby ustawić globalny język (menu, NSAlert itp.)
    // Jeśli użytkownik wybrał ręcznie język, wymusza go przez AppleLanguages.
    // Jeśli ustawione jest "auto":
    //  - jeśli język systemu jest wspierany -> usuwa override (system wybierze właściwą lokalizację)
    //  - jeśli niewspierany -> wymusza EN jako bezpieczny fallback
    static func applyPreferredLanguageAtLaunch() {
        let selected = UserDefaults.standard.string(forKey: "selected_language_v2") ?? "auto"
        if selected == "auto" {
            let primary = Locale.preferredLanguages.first?.replacingOccurrences(of: "_", with: "-") ?? "en"
            if isLanguageSupported(primary) {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
        } else {
            UserDefaults.standard.set([selected], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }
    
    @Published var needsRestart: Bool = false

    // ZMIANA: Nowy klucz, aby zresetować stare ustawienia.
    // Domyślna wartość to "auto" - oznacza "podążaj za systemem".
    @AppStorage("selected_language_v2") private var storedLanguage: String = "auto"
    
    // Informacja, czy aktywny jest tryb automatyczny (podążaj za systemem)
    var isAuto: Bool { storedLanguage == "auto" }
    
    // To jest właściwość, z której korzysta całe UI.
    var currentLanguage: String {
        get {
            if storedLanguage == "auto" {
                // Jeśli jest "auto", zawsze sprawdzamy aktualny język systemu
                return LanguageManager.detectSystemLanguage()
            } else {
                // Jeśli użytkownik coś wybrał ręcznie, używamy tego
                return storedLanguage
            }
        }
        set {
            // Zapisujemy ręczny wybór użytkownika
            // Od tego momentu aplikacja będzie pamiętać ten język
            objectWillChange.send()
            let oldValue = storedLanguage
            storedLanguage = newValue
            
            // --- Update global AppleLanguages for system UI ---
            if newValue == "auto" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                UserDefaults.standard.synchronize()
                if oldValue != newValue {
                    needsRestart = true
                }
            } else {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                UserDefaults.standard.synchronize()
                if oldValue != newValue {
                    needsRestart = true
                }
            }
        }
    }
    
    // Zwraca obiekt Locale dla wybranego języka
    var locale: Locale {
        return Locale(identifier: currentLanguage)
    }
    
    // --- FUNKCJA WYKRYWANIA JĘZYKA SYSTEMOWEGO ---
    static func detectSystemLanguage() -> String {
        // 1. Sprawdzamy preferowane języki użytkownika w systemie macOS
        // (Ustawienia -> Ogólne -> Język i region)
        guard let primaryLanguage = Locale.preferredLanguages.first else {
            return "en"
        }
        
        // Normalizacja: zamieniamy podkreślenia na myślniki (np. zh_Hans -> zh-Hans)
        let systemIdentifier = primaryLanguage.replacingOccurrences(of: "_", with: "-")
        
        // KROK A: Sprawdzenie dokładne (np. "pt-BR")
        if LanguageManager.supportedLanguages.contains(systemIdentifier) {
            return systemIdentifier
        }
        
        // KROK B: Sprawdzenie po kodzie języka (np. "de-DE" -> "de")
        // Dzielimy string po myślniku i bierzemy pierwszy człon
        let languageCode = systemIdentifier.components(separatedBy: "-").first ?? systemIdentifier
        
        if LanguageManager.supportedLanguages.contains(languageCode) {
            return languageCode
        }
        
        // KROK C: Sprawdzenie czy wspierany język jest 'rodzicem' (np. system "es-MX", wspieramy "es")
        for supported in LanguageManager.supportedLanguages {
            if systemIdentifier.hasPrefix(supported) {
                return supported
            }
        }
        
        // KROK D: Fallback - jeśli system jest w języku, którego nie wspieramy (np. Włoski), użyj Angielskiego
        return "en"
    }
}
