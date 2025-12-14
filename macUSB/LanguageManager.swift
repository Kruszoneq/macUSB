import SwiftUI
import Combine

class LanguageManager: ObservableObject {
    
    // ZMIANA: Nowy klucz, aby zresetować stare ustawienia.
    // Domyślna wartość to "auto" - oznacza "podążaj za systemem".
    @AppStorage("selected_language_v2") private var storedLanguage: String = "auto"
    
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
            storedLanguage = newValue
        }
    }
    
    // Zwraca obiekt Locale dla wybranego języka
    var locale: Locale {
        return Locale(identifier: currentLanguage)
    }
    
    // --- FUNKCJA WYKRYWANIA JĘZYKA SYSTEMOWEGO ---
    static func detectSystemLanguage() -> String {
        // Lista kodów wspieranych przez aplikację
        let supportedLanguages = [
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
        
        // 1. Sprawdzamy preferowane języki użytkownika w systemie macOS
        // (Ustawienia -> Ogólne -> Język i region)
        guard let primaryLanguage = Locale.preferredLanguages.first else {
            return "en"
        }
        
        // Normalizacja: zamieniamy podkreślenia na myślniki (np. zh_Hans -> zh-Hans)
        let systemIdentifier = primaryLanguage.replacingOccurrences(of: "_", with: "-")
        
        // KROK A: Sprawdzenie dokładne (np. "pt-BR")
        if supportedLanguages.contains(systemIdentifier) {
            return systemIdentifier
        }
        
        // KROK B: Sprawdzenie po kodzie języka (np. "de-DE" -> "de")
        // Dzielimy string po myślniku i bierzemy pierwszy człon
        let languageCode = systemIdentifier.components(separatedBy: "-").first ?? systemIdentifier
        
        if supportedLanguages.contains(languageCode) {
            return languageCode
        }
        
        // KROK C: Sprawdzenie czy wspierany język jest 'rodzicem' (np. system "es-MX", wspieramy "es")
        for supported in supportedLanguages {
            if systemIdentifier.hasPrefix(supported) {
                return supported
            }
        }
        
        // KROK D: Fallback - jeśli system jest w języku, którego nie wspieramy (np. Włoski), użyj Angielskiego
        return "en"
    }
}
