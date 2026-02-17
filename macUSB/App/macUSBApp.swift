import SwiftUI
import AppKit
import ServiceManagement

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
        NotificationPermissionManager.shared.refreshState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Reset external drives support on app termination
        UserDefaults.standard.set(false, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        // Reflect the state in MenuState for consistency
        MenuState.shared.externalDrivesEnabled = false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NotificationPermissionManager.shared.refreshState()
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
                .frame(width: MacUSBDesignTokens.windowWidth, height: MacUSBDesignTokens.windowHeight)
                .frame(
                    minWidth: MacUSBDesignTokens.windowWidth,
                    maxWidth: MacUSBDesignTokens.windowWidth,
                    minHeight: MacUSBDesignTokens.windowHeight,
                    maxHeight: MacUSBDesignTokens.windowHeight
                )
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
            
            CommandMenu(String(localized: "Opcje")) {
                Menu {
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
                } label: {
                    Label(String(localized: "Pomiń analizowanie pliku"), systemImage: "doc.text.magnifyingglass")
                }
                Divider()
                Button {
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
                } label: {
                    Label(String(localized: "Włącz obsługę zewnętrznych dysków twardych"), systemImage: "externaldrive.badge.plus")
                }
                Divider()
                Button {
                    resetExternalVolumeAccessPermissions()
                } label: {
                    Label(String(localized: "Resetuj uprawnienia dostępu do dysków zewnętrznych"), systemImage: "arrow.clockwise.circle")
                }
                Divider()
                Menu {
                    Button {
                        languageManager.currentLanguage = "auto"
                    } label: {
                        if languageManager.isAuto {
                            Label(String(localized: "Automatycznie"), systemImage: "checkmark")
                        } else {
                            Text(String(localized: "Automatycznie"))
                        }
                    }
                    Divider()
                    Button { languageManager.currentLanguage = "pl" } label: {
                        if languageManager.currentLanguage == "pl" {
                            Label("Polski", systemImage: "checkmark")
                        } else {
                            Text("Polski")
                        }
                    }
                    Button { languageManager.currentLanguage = "en" } label: {
                        if languageManager.currentLanguage == "en" {
                            Label("English", systemImage: "checkmark")
                        } else {
                            Text("English")
                        }
                    }
                    Button { languageManager.currentLanguage = "de" } label: {
                        if languageManager.currentLanguage == "de" {
                            Label("Deutsch", systemImage: "checkmark")
                        } else {
                            Text("Deutsch")
                        }
                    }
                    Button { languageManager.currentLanguage = "fr" } label: {
                        if languageManager.currentLanguage == "fr" {
                            Label("Français", systemImage: "checkmark")
                        } else {
                            Text("Français")
                        }
                    }
                    Button { languageManager.currentLanguage = "es" } label: {
                        if languageManager.currentLanguage == "es" {
                            Label("Español", systemImage: "checkmark")
                        } else {
                            Text("Español")
                        }
                    }
                    Button { languageManager.currentLanguage = "pt-BR" } label: {
                        if languageManager.currentLanguage == "pt-BR" {
                            Label("Português (BR)", systemImage: "checkmark")
                        } else {
                            Text("Português (BR)")
                        }
                    }
                    Button { languageManager.currentLanguage = "ru" } label: {
                        if languageManager.currentLanguage == "ru" {
                            Label("Русский", systemImage: "checkmark")
                        } else {
                            Text("Русский")
                        }
                    }
                    Button { languageManager.currentLanguage = "zh-Hans" } label: {
                        if languageManager.currentLanguage == "zh-Hans" {
                            Label("简体中文", systemImage: "checkmark")
                        } else {
                            Text("简体中文")
                        }
                    }
                    Button { languageManager.currentLanguage = "ja" } label: {
                        if languageManager.currentLanguage == "ja" {
                            Label("日本語", systemImage: "checkmark")
                        } else {
                            Text("日本語")
                        }
                    }
                    Button { languageManager.currentLanguage = "it" } label: {
                        if languageManager.currentLanguage == "it" {
                            Label("Italiano", systemImage: "checkmark")
                        } else {
                            Text("Italiano")
                        }
                    }
                    Button { languageManager.currentLanguage = "uk" } label: {
                        if languageManager.currentLanguage == "uk" {
                            Label("Українська", systemImage: "checkmark")
                        } else {
                            Text("Українська")
                        }
                    }
                    Button { languageManager.currentLanguage = "vi" } label: {
                        if languageManager.currentLanguage == "vi" {
                            Label("Tiếng Việt", systemImage: "checkmark")
                        } else {
                            Text("Tiếng Việt")
                        }
                    }
                    Button { languageManager.currentLanguage = "tr" } label: {
                        if languageManager.currentLanguage == "tr" {
                            Label("Türkçe", systemImage: "checkmark")
                        } else {
                            Text("Türkçe")
                        }
                    }
                } label: {
                    Label(String(localized: "Język"), systemImage: "globe")
                }
                Divider()
                Button {
                    NotificationPermissionManager.shared.handleMenuNotificationsTapped()
                } label: {
                    if menuState.notificationsEnabled {
                        Label(
                            String(localized: "Powiadomienia włączone"),
                            systemImage: "bell.and.waves.left.and.right"
                        )
                    } else {
                        Label(
                            String(localized: "Powiadomienia wyłączone"),
                            systemImage: "bell.slash"
                        )
                    }
                }
            }
            CommandMenu(String(localized: "Narzędzia")) {
                Button {
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
                } label: {
                    Label(String(localized: "Otwórz Narzędzie dyskowe"), systemImage: "externaldrive")
                }
                Divider()
                Button {
                    HelperServiceManager.shared.presentStatusAlert()
                } label: {
                    Label(String(localized: "Status helpera"), systemImage: "info.circle")
                }
                Button {
                    HelperServiceManager.shared.repairRegistrationFromMenu()
                } label: {
                    Label(String(localized: "Napraw helpera"), systemImage: "wrench.and.screwdriver")
                }
                Button {
                    SMAppService.openSystemSettingsLoginItems()
                } label: {
                    Label(String(localized: "Ustawienia działania w tle…"), systemImage: "gearshape")
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
            #if DEBUG
            CommandMenu("DEBUG") {
                Button(String(localized: "Przejdź do podsumowania (Big Sur) (2s delay)")) {
                    NotificationCenter.default.post(name: .macUSBDebugGoToBigSurSummary, object: nil)
                }
                Button(String(localized: "Przejdź do podsumowania (Tiger) (2s delay)")) {
                    NotificationCenter.default.post(name: .macUSBDebugGoToTigerSummary, object: nil)
                }
                Divider()
                Button(String(localized: "Otwórz macUSB_temp")) {
                    openMacUSBTempFolderInFinder()
                }
                Divider()
                Text(String(localized: "Informacje"))
                Text(verbatim: menuState.debugCopiedDataLabel)
            }
            #endif
        }
    }

    private func resetExternalVolumeAccessPermissions() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.kruszoneq.macUSB"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "SystemPolicyRemovableVolumes", bundleId]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if task.terminationStatus == 0 {
                presentExternalVolumePermissionsResetSuccessAlert()
            } else {
                presentExternalVolumePermissionsResetFailureAlert(bundleId: bundleId, details: output)
            }
        } catch {
            presentExternalVolumePermissionsResetFailureAlert(bundleId: bundleId, details: error.localizedDescription)
        }
    }

    private func presentExternalVolumePermissionsResetSuccessAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Wyczyszczono uprawnienia dostępu do dysków zewnętrznych")
        alert.informativeText = String(localized: "Uprawnienia aplikacji macUSB do nośników zewnętrznych zostały zresetowane. Przy kolejnej próbie tworzenia nośnika system poprosi ponownie o zgodę.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private func presentExternalVolumePermissionsResetFailureAlert(bundleId: String, details: String?) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Nie udało się wyczyścić uprawnień dostępu do dysków zewnętrznych")
        var informativeText = String.localizedStringWithFormat(
            String(localized: "Nie udało się zresetować uprawnień dostępu do nośników zewnętrznych. Spróbuj ponownie lub uruchom ręcznie w Terminalu: tccutil reset SystemPolicyRemovableVolumes %@"),
            bundleId
        )
        if let details, !details.isEmpty {
            informativeText += "\n\n\(details)"
        }
        alert.informativeText = informativeText
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    #if DEBUG
    private func openMacUSBTempFolderInFinder() {
        let tempFolderURL = FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_temp", isDirectory: true)
        guard FileManager.default.fileExists(atPath: tempFolderURL.path) else {
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Wybrany folder nie istnieje")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            return
        }

        NSWorkspace.shared.open(tempFolderURL)
    }
    #endif
}
