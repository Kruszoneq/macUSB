import SwiftUI
import AppKit
import Combine
import OSLog

private enum AppRoute: Hashable {
    case debugFinishUSBBigSurSuccess
    case debugFinishUSBTigerSuccess
}

struct ContentView: View {
    @State private var path = NavigationPath()
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var pendingDebugNavigationWorkItem: DispatchWorkItem?

    private var debugMountPointURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_debug_mount_point")
    }

    private var debugCleanupTempWorkURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_debug_temp")
    }

    private var debugTigerMountPointURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_debug_tiger_mount_point")
    }

    private var debugTigerCleanupTempWorkURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_debug_tiger_temp")
    }
    
    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                rootView
                    .toolbarBackgroundVisibility(.automatic, for: .windowToolbar)
            } else {
                rootView
            }
        }
    }

    private var rootView: some View {
        NavigationStack(path: $path) {
            WelcomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .debugFinishUSBBigSurSuccess:
                        FinishUSBView(
                            systemName: "macOS Big Sur 11",
                            mountPoint: debugMountPointURL,
                            onReset: {
                                NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                                path = NavigationPath()
                            },
                            isPPC: false,
                            didFail: false,
                            cleanupTempWorkURL: debugCleanupTempWorkURL,
                            shouldDetachMountPoint: false
                        )
                    case .debugFinishUSBTigerSuccess:
                        FinishUSBView(
                            systemName: "Mac OS X Tiger 10.4",
                            mountPoint: debugTigerMountPointURL,
                            onReset: {
                                NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
                                path = NavigationPath()
                            },
                            isPPC: true,
                            didFail: false,
                            cleanupTempWorkURL: debugTigerCleanupTempWorkURL,
                            shouldDetachMountPoint: false
                        )
                    }
                }
        }
        // Sztywny rozmiar kontentu
        .frame(width: MacUSBDesignTokens.windowWidth, height: MacUSBDesignTokens.windowHeight)
        // Podpięcie konfiguratora okna
        .background(WindowConfigurator())
        // Wstrzyknięcie języka
        .environment(\.locale, languageManager.locale)
        // Wymuszenie odświeżenia przy zmianie języka
        .id(languageManager.currentLanguage)
        .onChange(of: languageManager.needsRestart) { needsRestart in
            if needsRestart {
                presentRestartAlert()
            }
        }
        .onAppear {
            AppLogging.logAppStartupOnce()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macUSBDebugGoToBigSurSummary)) { _ in
            scheduleDebugSummaryNavigation(
                route: .debugFinishUSBBigSurSuccess,
                logMessage: "DEBUG: Zaplanowano przejście do podsumowania Big Sur za 2 sekundy"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .macUSBDebugGoToTigerSummary)) { _ in
            scheduleDebugSummaryNavigation(
                route: .debugFinishUSBTigerSuccess,
                logMessage: "DEBUG: Zaplanowano przejście do podsumowania Tiger (isPPC) za 2 sekundy"
            )
        }
    }

    private func scheduleDebugSummaryNavigation(route: AppRoute, logMessage: String) {
        AppLogging.info(logMessage, category: "Navigation")
        pendingDebugNavigationWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            NotificationCenter.default.post(name: .macUSBResetToStart, object: nil)
            path = NavigationPath()
            path.append(route)
            pendingDebugNavigationWorkItem = nil
        }

        pendingDebugNavigationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func restartApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        try? task.run()
        NSApp.terminate(nil)
    }
    
    private func presentRestartAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "Wymagany restart aplikacji")
        alert.informativeText = String(localized: "Aby zmienić język interfejsu we wszystkich elementach aplikacji (w tym menu i przyciskach), wymagany jest restart. Kliknij poniżej, aby uruchomić aplikację ponownie.")
        alert.addButton(withTitle: String(localized: "Uruchom aplikację ponownie"))

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    restartApp()
                }
                languageManager.needsRestart = false
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                restartApp()
            }
            languageManager.needsRestart = false
        }
    }
}

// --- KONFIGURACJA OKNA ---

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                // 1. Ustawienie sztywnych wymiarów
                let fixedSize = NSSize(width: MacUSBDesignTokens.windowWidth, height: MacUSBDesignTokens.windowHeight)
                window.minSize = fixedSize
                window.maxSize = fixedSize
                // Wyłączenie możliwości zmiany rozmiaru na poziomie systemu
                window.styleMask.remove(.resizable)

                if window.toolbar == nil {
                    window.toolbar = NSToolbar(identifier: "com.kruszoneq.macusb.window.toolbar")
                }
                if #available(macOS 11.0, *) {
                    window.toolbarStyle = .unifiedCompact
                }
                
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
