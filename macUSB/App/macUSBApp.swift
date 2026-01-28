import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Ensure external drives support is disabled by default on launch
        UserDefaults.standard.set(false, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        // Update MenuState to reflect the default state in UI
        MenuState.shared.externalDrivesEnabled = false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Reset external drives support on app termination
        UserDefaults.standard.set(false, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        // Reflect the state in MenuState for consistency
        MenuState.shared.externalDrivesEnabled = false
    }
}

@main
struct macUSBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var menuState = MenuState.shared
    
    init() {
        // Ustaw globalny język jak najwcześniej (na podstawie wyboru użytkownika lub systemu)
        LanguageManager.applyPreferredLanguageAtLaunch()
        
        // Blokada przed podwójnym uruchomieniem
        if let bundleId = Bundle.main.bundleIdentifier {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if runningApps.count > 1 {
                for app in runningApps where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    if #available(macOS 14.0, *) {
                        app.activate()
                    } else {
                        app.activate(options: [])
                    }
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
            
            CommandMenu(String(localized: "Opcje")) {
                Menu(String(localized: "Pomiń analizowanie pliku")) {
                    Button(String(localized: "Mac OS X Tiger 10.4 (Multi DVD)")) {
                        let alert = NSAlert()
                        alert.alertStyle = .informational
                        alert.icon = NSApp.applicationIconImage
                        alert.messageText = String(localized: "Tworzenie USB z Mac OS X Tiger (Multi DVD)")
                        alert.informativeText = String(localized: "Dla wybranego obrazu zostanie pominięta weryfikacja wersji. Aplikacja wymusi rozpoznanie pliku jako „Mac OS X Tiger 10.4”, aby umożliwić jego zamontowanie i zapis na USB. Czy chcesz kontynuować?")
                        alert.addButton(withTitle: String(localized: "Nie"))
                        alert.addButton(withTitle: String(localized: "Tak"))
                        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                            alert.beginSheetModal(for: window) { response in
                                if response == .alertSecondButtonReturn {
                                    NotificationCenter.default.post(name: .macUSBStartTigerMultiDVD, object: nil)
                                }
                            }
                        } else {
                            let response = alert.runModal()
                            if response == .alertSecondButtonReturn {
                                NotificationCenter.default.post(name: .macUSBStartTigerMultiDVD, object: nil)
                            }
                        }
                    }
                    .keyboardShortcut("t", modifiers: [.option, .command])
                    .disabled(!menuState.skipAnalysisEnabled)
                }
                Divider()
                Button(String(localized: "Włącz obsługę dysków zewnętrznych")) {
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.icon = NSApp.applicationIconImage
                    alert.messageText = String(localized: "Włącz obsługę dysków zewnętrznych")
                    alert.informativeText = String(localized: "Ta funkcja umożliwia tworzenie instalatora na zewnętrznych dyskach twardych i SSD. Zachowaj szczególną ostrożność przy wyborze dysku docelowego z listy, aby uniknąć przypadkowej utraty danych!")
                    alert.addButton(withTitle: String(localized: "OK"))

                    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                        alert.beginSheetModal(for: window) { _ in menuState.enableExternalDrives() }
                    } else {
                        _ = alert.runModal()
                        menuState.enableExternalDrives()
                    }
                }
            }
            CommandGroup(replacing: .windowList) { }
            CommandGroup(after: .appInfo) {
                Button {
                    UpdateChecker.shared.checkFromMenu()
                } label: {
                    Label(String(localized: "Sprawdź dostępność aktualizacji"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            CommandGroup(after: .help) {
                Divider()
                Button {
                    if let url = URL(string: "https://kruszoneq.github.io/macUSB/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "Strona internetowa macUSB"), systemImage: "globe")
                }
                Button {
                    if let url = URL(string: "https://github.com/Kruszoneq/macUSB/issues") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "Zgłoś błąd (GitHub)"), systemImage: "exclamationmark.triangle")
                }
            }
        }
    }
}

