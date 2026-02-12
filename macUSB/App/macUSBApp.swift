import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var debugMenuHandler: DebugMenuHandler?
    private var debugMenuObservers: [NSObjectProtocol] = []
    private let debugMenuTitle = "DEBUG"

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
        NotificationPermissionManager.shared.refreshState()

        configureDebugMenuObservers()

        DispatchQueue.main.async {
            if self.isRunningFromXcode {
                self.installDebugMenuIfNeeded()
            } else {
                self.uninstallDebugMenuIfNeeded()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Reset external drives support on app termination
        UserDefaults.standard.set(false, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        // Reflect the state in MenuState for consistency
        MenuState.shared.externalDrivesEnabled = false

        for observer in debugMenuObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        debugMenuObservers.removeAll()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NotificationPermissionManager.shared.refreshState()
    }

    private var isRunningFromXcode: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCODE_VERSION_ACTUAL"] != nil || env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
    }

    private func configureDebugMenuObservers() {
        let center = NotificationCenter.default
        let didAppearObserver = center.addObserver(
            forName: .macUSBWelcomeViewDidAppear,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.isRunningFromXcode else {
                self.uninstallDebugMenuIfNeeded()
                return
            }
            self.installDebugMenuIfNeeded()
        }

        let didDisappearObserver = center.addObserver(
            forName: .macUSBWelcomeViewDidDisappear,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.uninstallDebugMenuIfNeeded()
        }

        debugMenuObservers = [didAppearObserver, didDisappearObserver]
    }

    private func installDebugMenuIfNeeded() {
        guard let mainMenu = NSApp.mainMenu else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.installDebugMenuIfNeeded()
            }
            return
        }
        guard !mainMenu.items.contains(where: { $0.title == debugMenuTitle }) else { return }

        let topLevelItem = NSMenuItem(title: debugMenuTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: debugMenuTitle)

        let handler = DebugMenuHandler()
        let goToBigSurSummaryItem = NSMenuItem(
            title: String(localized: "Przejdź do podsumowania (Big Sur)"),
            action: #selector(DebugMenuHandler.goToBigSurSummary),
            keyEquivalent: ""
        )
        goToBigSurSummaryItem.target = handler

        let goToTigerSummaryItem = NSMenuItem(
            title: String(localized: "Przejdź do podsumowania (Tiger)"),
            action: #selector(DebugMenuHandler.goToTigerSummary),
            keyEquivalent: ""
        )
        goToTigerSummaryItem.target = handler

        submenu.addItem(goToBigSurSummaryItem)
        submenu.addItem(goToTigerSummaryItem)
        topLevelItem.submenu = submenu
        mainMenu.addItem(topLevelItem)

        self.debugMenuHandler = handler
    }

    private func uninstallDebugMenuIfNeeded() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let index = mainMenu.items.firstIndex(where: { $0.title == debugMenuTitle }) else { return }
        mainMenu.removeItem(at: index)
    }
}

private final class DebugMenuHandler: NSObject {
    @objc func goToBigSurSummary() {
        NotificationCenter.default.post(name: .macUSBDebugGoToBigSurSummary, object: nil)
    }

    @objc func goToTigerSummary() {
        NotificationCenter.default.post(name: .macUSBDebugGoToTigerSummary, object: nil)
    }
}

@main
struct macUSBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var menuState = MenuState.shared
    @StateObject private var languageManager = LanguageManager()
    
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
                .environmentObject(languageManager)
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
                Button(String(localized: "Włącz obsługę zewnętrznych dysków twardych")) {
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.icon = NSApp.applicationIconImage
                    alert.messageText = String(localized: "Włącz obsługę zewnętrznych dysków twardych")
                    alert.informativeText = String(localized: "Ta funkcja umożliwia tworzenie instalatora na zewnętrznych dyskach twardych i SSD. Zachowaj szczególną ostrożność przy wyborze dysku docelowego z listy, aby uniknąć przypadkowej utraty danych!")
                    alert.addButton(withTitle: String(localized: "OK"))

                    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                        alert.beginSheetModal(for: window) { _ in menuState.enableExternalDrives() }
                    } else {
                        _ = alert.runModal()
                        menuState.enableExternalDrives()
                    }
                }
                Divider()
                Menu(String(localized: "Język")) {
                    Button {
                        languageManager.currentLanguage = "auto"
                    } label: {
                        Label(String(localized: "Automatycznie"), systemImage: languageManager.isAuto ? "checkmark" : "")
                    }
                    Divider()
                    Button { languageManager.currentLanguage = "pl" } label: {
                        Label("Polski", systemImage: languageManager.currentLanguage == "pl" ? "checkmark" : "")
                    }
                    Button { languageManager.currentLanguage = "en" } label: {
                        Label("English", systemImage: languageManager.currentLanguage == "en" ? "checkmark" : "")
                    }
                    Button { languageManager.currentLanguage = "de" } label: {
                        Label("Deutsch", systemImage: languageManager.currentLanguage == "de" ? "checkmark" : "")
                    }
                    Button { languageManager.currentLanguage = "fr" } label: {
                        Label("Français", systemImage: languageManager.currentLanguage == "fr" ? "checkmark" : "")
                    }
                    Button { languageManager.currentLanguage = "es" } label: {
                        Label("Español", systemImage: languageManager.currentLanguage == "es" ? "checkmark" : "")
                    }
                    Button { languageManager.currentLanguage = "pt-BR" } label: {
                        Label("Português (BR)", systemImage: languageManager.currentLanguage == "pt-BR" ? "checkmark" : "")
                    }
                    Button { languageManager.currentLanguage = "ru" } label: {
                        Label("Русский", systemImage: languageManager.currentLanguage == "ru" ? "checkmark" : "")
                    }
                    Button { languageManager.currentLanguage = "zh-Hans" } label: {
                        Label("简体中文", systemImage: languageManager.currentLanguage == "zh-Hans" ? "checkmark" : "")
                    }
                    Button { languageManager.currentLanguage = "ja" } label: {
                        Label("日本語", systemImage: languageManager.currentLanguage == "ja" ? "checkmark" : "")
                    }
                }
                Divider()
                Button {
                    NotificationPermissionManager.shared.handleMenuNotificationsTapped()
                } label: {
                    Label(String(localized: "Powiadomienia"), systemImage: menuState.notificationsEnabled ? "checkmark" : "")
                }
            }
            CommandMenu(String(localized: "Narzędzia")) {
                Button(String(localized: "Otwórz Narzędzie dyskowe")) {
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.DiskUtility") {
                        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                    } else {
                        let candidatePaths = [
                            "/System/Applications/Utilities/Disk Utility.app",
                            "/Applications/Utilities/Disk Utility.app"
                        ]
                        for path in candidatePaths {
                            if FileManager.default.fileExists(atPath: path) {
                                let url = URL(fileURLWithPath: path, isDirectory: true)
                                NSWorkspace.shared.open(url)
                                break
                            }
                        }
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
                    if let url = URL(string: "https://github.com/Kruszoneq/macUSB") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "Repozytorium macUSB na GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button {
                    if let url = URL(string: "https://github.com/Kruszoneq/macUSB/issues") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "Zgłoś błąd (GitHub)"), systemImage: "exclamationmark.triangle")
                }
                Divider()
                Button {
                    if let url = URL(string: "https://buymeacoffee.com/kruszoneq") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "Wesprzyj projekt macUSB"), systemImage: "cup.and.saucer")
                }
                Divider()
                Button {
                    let savePanel = NSSavePanel()
                    let defaults = UserDefaults.standard
                    if let lastPath = defaults.string(forKey: "DiagnosticsExportLastDirectory") {
                        let lastURL = URL(fileURLWithPath: lastPath, isDirectory: true)
                        if FileManager.default.fileExists(atPath: lastURL.path) {
                            savePanel.directoryURL = lastURL
                        } else {
                            savePanel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                        }
                    } else {
                        savePanel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                    }
                    savePanel.allowedFileTypes = ["txt"]
                    let df = DateFormatter()
                    df.dateFormat = "yyyyMMdd_HHmmss"
                    savePanel.nameFieldStringValue = "macUSB_\(df.string(from: Date()))_logs.txt"
                    savePanel.canCreateDirectories = true
                    savePanel.isExtensionHidden = false
                    savePanel.title = String(localized: "Eksportuj logi diagnostyczne")
                    savePanel.message = String(localized: "Wybierz miejsce zapisu pliku z logami diagnostycznymi")
                    if savePanel.runModal() == .OK, let url = savePanel.url {
                        let text = AppLogging.exportedLogText()
                        do {
                            try text.data(using: .utf8)?.write(to: url)
                            let dir = url.deletingLastPathComponent()
                            UserDefaults.standard.set(dir.path, forKey: "DiagnosticsExportLastDirectory")
                        } catch {
                            let alert = NSAlert()
                            alert.icon = NSApp.applicationIconImage
                            alert.alertStyle = .warning
                            alert.messageText = String(localized: "Nie udało się zapisać pliku z logami")
                            alert.informativeText = error.localizedDescription
                            alert.addButton(withTitle: String(localized: "OK"))
                            alert.runModal()
                        }
                    }
                } label: {
                    Label(String(localized: "Eksportuj logi diagnostyczne..."), systemImage: "square.and.arrow.down")
                }
            }
        }
    }
}
