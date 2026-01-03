import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @State private var path = NavigationPath()
    
    // Teraz Xcode znajdzie klasę w pliku LanguageManager.swift
    @StateObject private var languageManager = LanguageManager()
    
    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView()
                .environmentObject(languageManager)
        }
        // Sztywny rozmiar kontentu
        .frame(width: 550, height: 750)
        // Podpięcie konfiguratora okna
        .background(WindowConfigurator())
        // Wstrzyknięcie języka
        .environment(\.locale, languageManager.locale)
        // Wymuszenie odświeżenia przy zmianie języka
        .id(languageManager.currentLanguage)
    }
}

// --- KONFIGURACJA OKNA ---

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                // 1. Ustawienie sztywnych wymiarów
                let fixedSize = NSSize(width: 550, height: 750)
                window.minSize = fixedSize
                window.maxSize = fixedSize
                // Wyłączenie możliwości zmiany rozmiaru na poziomie systemu
                window.styleMask.remove(.resizable)
                
                // 2. Wyśrodkowanie i konfiguracja przycisków
                window.center()
                window.collectionBehavior = [.fullScreenNone, .managed]
                
                // Wyłączenie przycisku maksymalizacji (zielony)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                // Pozostałe przyciski aktywne
                window.standardWindowButton(.closeButton)?.isEnabled = true
                window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
                
                // Ustawienie tytułu
                window.title = "macUSB"
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// USUNIĘTO KLASĘ LanguageManager STĄD, ABY UNIKNĄĆ DUPLIKACJI

