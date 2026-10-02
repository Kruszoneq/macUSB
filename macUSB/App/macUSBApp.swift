import SwiftUI
import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppTerminationCoordinator.shared.applicationShouldTerminate()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Ensure external drives support is disabled by default on launch
        UserDefaults.standard.set(false, forKey: "AllowExternalDrives")
        UserDefaults.standard.synchronize()
        // Update MenuState to reflect the default state in UI
        MenuState.shared.externalDrivesEnabled = false
        refreshPermissionStates(fullDiskAccessTrigger: nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        let cleanupSucceeded = AppTerminationCleanup.shared.performIfNeeded()
        AppLogging.finishSession(cleanupSucceeded: cleanupSucceeded)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshPermissionStates(fullDiskAccessTrigger: .activation)
    }

    private func refreshPermissionStates(fullDiskAccessTrigger: FullDiskAccessCheckTrigger?) {
        NotificationPermissionManager.shared.refreshState()
        if let fullDiskAccessTrigger {
            FullDiskAccessPermissionManager.shared.refreshState(trigger: fullDiskAccessTrigger)
        }
        HelperServiceManager.shared.refreshBackgroundApprovalState()
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
                return
            }
        }
        AppLogging.startSession()
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
            
            CommandMenu(String(localized: "app.menu.options.title", table: "App")) {
                Menu {
                    Button(String(localized: "app.macos.tiger.menu.multi_dvd", table: "App")) {
                        let alert = NSAlert()
                        alert.alertStyle = .informational
                        alert.icon = NSApp.applicationIconImage
                        alert.messageText = String(localized: "app.macos.tiger.override.title", table: "App")
                        alert.informativeText = String(localized: "app.macos.tiger.override.message", table: "App")
                        alert.addButton(withTitle: String(localized: "app.action.no", table: "App"))
                        alert.addButton(withTitle: String(localized: "app.action.yes", table: "App"))
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
                    Label(String(localized: "app.macos.menu.skip_analysis", table: "App"), systemImage: "doc.text.magnifyingglass")
                }
                Divider()
                Button {
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.icon = NSApp.applicationIconImage
                    alert.messageText = String(localized: "app.external_drives.enable.title", table: "App")
                    alert.informativeText = String(localized: "app.external_drives.enable.message", table: "App")
                    alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))

                    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                        alert.beginSheetModal(for: window) { _ in menuState.enableExternalDrives() }
                    } else {
                        _ = alert.runModal()
                        menuState.enableExternalDrives()
                    }
                } label: {
                    Label(String(localized: "app.external_drives.enable.title", table: "App"), systemImage: "externaldrive.badge.plus")
                }
                Divider()
                Button {
                    resetExternalVolumeAccessPermissions()
                } label: {
                    Label(String(localized: "app.external_drives.permissions.reset.menu", table: "App"), systemImage: "arrow.clockwise.circle")
                }
                Divider()
                Menu {
                    Button {
                        languageManager.currentLanguage = "auto"
                    } label: {
                        if languageManager.isAuto {
                            Label(String(localized: "app.language.automatic", table: "App"), systemImage: "checkmark")
                        } else {
                            Text(String(localized: "app.language.automatic", table: "App"))
                        }
                    }
                    Divider()
                    Button { languageManager.currentLanguage = "pl" } label: {
                        if languageManager.currentLanguage == "pl" {
                            Label(String(localized: "app.language.name.pl", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.pl", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "en" } label: {
                        if languageManager.currentLanguage == "en" {
                            Label(String(localized: "app.language.name.en", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.en", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "de" } label: {
                        if languageManager.currentLanguage == "de" {
                            Label(String(localized: "app.language.name.de", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.de", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "fr" } label: {
                        if languageManager.currentLanguage == "fr" {
                            Label(String(localized: "app.language.name.fr", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.fr", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "es" } label: {
                        if languageManager.currentLanguage == "es" {
                            Label(String(localized: "app.language.name.es", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.es", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "pt-BR" } label: {
                        if languageManager.currentLanguage == "pt-BR" {
                            Label(String(localized: "app.language.name.pt_br", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.pt_br", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "ru" } label: {
                        if languageManager.currentLanguage == "ru" {
                            Label(String(localized: "app.language.name.ru", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.ru", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "zh-Hans" } label: {
                        if languageManager.currentLanguage == "zh-Hans" {
                            Label(String(localized: "app.language.name.zh_hans", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.zh_hans", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "ja" } label: {
                        if languageManager.currentLanguage == "ja" {
                            Label(String(localized: "app.language.name.ja", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.ja", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "it" } label: {
                        if languageManager.currentLanguage == "it" {
                            Label(String(localized: "app.language.name.it", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.it", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "uk" } label: {
                        if languageManager.currentLanguage == "uk" {
                            Label(String(localized: "app.language.name.uk", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.uk", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "vi" } label: {
                        if languageManager.currentLanguage == "vi" {
                            Label(String(localized: "app.language.name.vi", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.vi", tableName: "App")
                        }
                    }
                    Button { languageManager.currentLanguage = "tr" } label: {
                        if languageManager.currentLanguage == "tr" {
                            Label(String(localized: "app.language.name.tr", table: "App"), systemImage: "checkmark")
                        } else {
                            Text("app.language.name.tr", tableName: "App")
                        }
                    }
                } label: {
                    Label(String(localized: "app.language.menu.title", table: "App"), systemImage: "globe")
                }
                .disabled(!menuState.isLanguageChangeEnabled)
                Divider()
                Button {
                    NotificationPermissionManager.shared.handleMenuNotificationsTapped()
                } label: {
                    if menuState.notificationsEnabled {
                        Label(
                            String(localized: "app.notifications.menu.enabled", table: "App"),
                            systemImage: "bell.and.waves.left.and.right"
                        )
                    } else {
                        Label(
                            String(localized: "app.notifications.menu.disabled", table: "App"),
                            systemImage: "bell.slash"
                        )
                    }
                }
            }
            CommandMenu(String(localized: "app.menu.tools.title", table: "App")) {
                Button {
                    MacOSDownloaderWindowManager.shared.present()
                } label: {
                    Label(String(localized: "app.macos.menu.download_installer", table: "App"), systemImage: "square.and.arrow.down")
                }
                .disabled(menuState.isDownloaderAccessBlocked)
                Divider()
                Button {
                    RawLinuxImageSelectionCoordinator.shared.presentSelectionFlow()
                } label: {
                    Label(String(localized: "app.raw_image.menu.write", table: "App"), systemImage: "externaldrive.fill.badge.plus")
                }
                .disabled(!menuState.rawLinuxImageSelectionEnabled)
                Divider()
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
                    Label(String(localized: "app.menu.tools.disk_utility", table: "App"), systemImage: "externaldrive")
                }
                Divider()
                Button {
                    HelperServiceManager.shared.presentStatusAlert()
                } label: {
                    Label(String(localized: "app.helper.menu.status", table: "App"), systemImage: "info.circle")
                }
                Button {
                    HelperServiceManager.shared.repairRegistrationFromMenu()
                } label: {
                    Label(String(localized: "app.helper.menu.repair", table: "App"), systemImage: "wrench.and.screwdriver")
                }
                Divider()
                Button {
                    SMAppService.openSystemSettingsLoginItems()
                } label: {
                    Label(String(localized: "app.permissions.background.menu", table: "App"), systemImage: "gearshape")
                }
                Button {
                    FullDiskAccessPermissionManager.shared.openFullDiskAccessSettings(showFallbackAlertIfNeeded: true)
                } label: {
                    Label(String(localized: "app.permissions.full_disk_access.menu", table: "App"), systemImage: "lock.shield")
                }
            }
            CommandGroup(replacing: .windowList) { }
            CommandGroup(after: .appInfo) {
                Button {
                    UpdateChecker.shared.checkFromMenu()
                } label: {
                    Label(String(localized: "app.update.menu.check", table: "App"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            CommandGroup(after: .help) {
                Divider()
                Button {
                    if let url = URL(string: "https://macusb.app/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "app.menu.help.website", table: "App"), systemImage: "globe")
                }
                Button {
                    if let url = URL(string: "https://github.com/Kruszoneq/macUSB") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "app.menu.help.repository", table: "App"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button {
                    if let url = URL(string: "https://github.com/Kruszoneq/macUSB/issues") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "app.menu.help.report_bug", table: "App"), systemImage: "exclamationmark.triangle")
                }
                Divider()
                Button {
                    if let url = URL(string: "https://buymeacoffee.com/kruszoneq") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "app.menu.help.support_project", table: "App"), systemImage: "cup.and.saucer")
                }
                Divider()
                Button {
                    exportDiagnosticLogs(previousSession: false)
                } label: {
                    Label(String(localized: "app.diagnostics.export.current.menu", table: "App"), systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("l", modifiers: [.option])
                Button {
                    exportDiagnosticLogs(previousSession: true)
                } label: {
                    Label(String(localized: "app.diagnostics.export.previous.menu", table: "App"), systemImage: "square.and.arrow.down")
                }
                .disabled(!AppLogging.hasPreviousSessionLogs)
            }
            #if DEBUG
            CommandMenu(Text(verbatim: "DEBUG")) {
                Button {
                    NotificationCenter.default.post(name: .macUSBDebugGoToBigSurSummary, object: nil)
                } label: {
                    Text(verbatim: "Go to Summary (Big Sur) (2s delay)")
                }
                Button {
                    NotificationCenter.default.post(name: .macUSBDebugGoToTigerSummary, object: nil)
                } label: {
                    Text(verbatim: "Go to Summary (Tiger) (2s delay)")
                }
                Button {
                    NotificationCenter.default.post(name: .macUSBDebugGoToLinuxSummary, object: nil)
                } label: {
                    Text(verbatim: "Go to Linux Summary (2s delay)")
                }
                Divider()
                Button {
                    openMacUSBTempFolderInFinder()
                } label: {
                    Text(verbatim: "Open macUSB_temp")
                }
                Button {
                    NSWorkspace.shared.open(AppLogging.diagnosticLogsDirectoryURL)
                } label: {
                    Text(verbatim: "Open Diagnostic Logs Folder")
                }
                Divider()
                Text(verbatim: "Information")
                Text(verbatim: menuState.debugCopiedDataLabel)
            }
            #endif
        }
    }

    private func exportDiagnosticLogs(previousSession: Bool) {
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
        savePanel.allowedFileTypes = ["log"]
        let df = DateFormatter()
        df.dateFormat = "yyMMdd-HHmmss"
        let prefix = previousSession ? "macUSB-prev" : "macUSB"
        savePanel.nameFieldStringValue = "\(prefix)-\(df.string(from: Date())).log"
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = previousSession
            ? String(localized: "app.diagnostics.export.previous.panel.title", table: "App")
            : String(localized: "app.diagnostics.export.current.panel.title", table: "App")
        savePanel.message = previousSession
            ? String(localized: "app.diagnostics.export.previous.panel.message", table: "App")
            : String(localized: "app.diagnostics.export.current.panel.message", table: "App")
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        do {
            if previousSession {
                try AppLogging.exportPreviousSession(to: url)
            } else {
                try Data(AppLogging.prepareExportedLogText().utf8).write(to: url)
            }
            defaults.set(url.deletingLastPathComponent().path, forKey: "DiagnosticsExportLastDirectory")
        } catch {
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.alertStyle = .warning
            alert.messageText = String(localized: "app.diagnostics.export.failure.title", table: "App")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
            alert.runModal()
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
        alert.messageText = String(localized: "app.external_drives.permissions.reset.success.title", table: "App")
        alert.informativeText = String(localized: "app.external_drives.permissions.reset.success.message", table: "App")
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        alert.runModal()
    }

    private func presentExternalVolumePermissionsResetFailureAlert(bundleId: String, details: String?) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "app.external_drives.permissions.reset.failure.title", table: "App")
        var informativeText = String.localizedStringWithFormat(
            String(localized: "app.external_drives.permissions.reset.failure.message", table: "App"),
            bundleId
        )
        if let details, !details.isEmpty {
            informativeText += "\n\n\(details)"
        }
        alert.informativeText = informativeText
        alert.addButton(withTitle: String(localized: "app.action.ok", table: "App"))
        alert.runModal()
    }

    #if DEBUG
    private func openMacUSBTempFolderInFinder() {
        let tempFolderURL = FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_temp", isDirectory: true)
        guard FileManager.default.fileExists(atPath: tempFolderURL.path) else {
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.alertStyle = .warning
            alert.messageText = "The selected folder does not exist"
            alert.informativeText = "The macUSB_temp folder has not been created or has already been removed."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        NSWorkspace.shared.open(tempFolderURL)
    }
    #endif
}
