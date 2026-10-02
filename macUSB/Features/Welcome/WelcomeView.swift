import SwiftUI
import AppKit

struct WelcomeView: View {
    
    // Odbieramy menedżera języka
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var dummyLock: Bool = false
    @State private var didRunStartupFlow: Bool = false
    @State private var navigateToAnalysis: Bool = false
    @State private var isSupportProjectHovered: Bool = false
    
    let versionCheckURL = URL(string: "https://raw.githubusercontent.com/Kruszoneq/macUSB/main/version.json")!
    let supportProjectURL = URL(string: "https://buymeacoffee.com/kruszoneq")!
    
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

            Text(verbatim: MacUSBBranding.appName)
                .font(.system(size: 40 * MacUSBDesignTokens.headlineScale(for: visualMode), weight: .semibold))
            
            // Opis z obsługą tłumaczeń
            Text(verbatim: MacUSBBranding.welcomeSlogan)
                .font(.system(size: 17 * MacUSBDesignTokens.subheadlineScale(for: visualMode), weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.horizontal, 72)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            // --- PRZYCISK START ---
            Button {
                navigateToAnalysis = true
            } label: {
                HStack {
                    Text("app.welcome.action.start", tableName: "App") // Klucz do tłumaczenia
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
                HStack(spacing: 6) {
                    Text("app.welcome.footer.credit", tableName: "App")
                    Text(verbatim: "•")
                    Link(destination: supportProjectURL) {
                        Text(String(localized: "app.welcome.footer.support_project", table: "App"))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(isSupportProjectHovered ? 0.22 : 0.0))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isSupportProjectHovered = isHovered
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 25)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(Text("app.welcome.navigation.title", tableName: "App"))
        .background(
            NavigationLink(
                destination: SystemAnalysisView(isTabLocked: $dummyLock),
                isActive: $navigateToAnalysis
            ) { EmptyView() }
            .hidden()
        )
        .onReceive(NotificationCenter.default.publisher(for: .macUSBNavigateToAnalysis)) { _ in
            navigateToAnalysis = true
        }
        .onAppear {
            MenuState.shared.resetLanguageChangesForWelcome()
            MenuState.shared.rawLinuxImageSelectionEnabled = true
            guard !didRunStartupFlow else { return }
            didRunStartupFlow = true
            runStartupFlow()
        }
        .onDisappear {
            MenuState.shared.rawLinuxImageSelectionEnabled = false
        }
    }

    private func runStartupFlow() {
        FullDiskAccessPermissionManager.shared.handleStartupPromptIfNeeded {
            HelperServiceManager.shared.bootstrapIfNeededAtStartup { _ in
                NotificationPermissionManager.shared.handleStartupFlowIfNeeded()
                self.checkForUpdates { }
            }
        }
    }
    
    func checkForUpdates(completion: @escaping () -> Void) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        AppLogging.info("Update check started: trigger=startup, currentVersion=\(currentVersion).", stage: .app)
        
        URLSession.shared.dataTask(with: versionCheckURL) { data, response, error in
            let finishOnMain: () -> Void = {
                DispatchQueue.main.async {
                    completion()
                }
            }

            guard let data = data, error == nil else {
                AppLogging.error("Update check failed: trigger=startup, details=\(error?.localizedDescription ?? "response data missing").", stage: .app)
                finishOnMain()
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
                   let remoteVersion = json["version"],
                   let downloadLink = json["url"] {
                    
                    if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                        AppLogging.info("Update check completed: trigger=startup, newerVersion=\(remoteVersion), currentVersion=\(currentVersion).", stage: .app)
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.icon = NSApplication.shared.applicationIconImage
                            alert.alertStyle = .informational
                            alert.messageText = String(localized: "app.update.available.title", table: "App")
                            let remoteVersionLine = String(format: String(localized: "app.update.available.message", table: "App"), remoteVersion)
                            let currentVersionLine = String(format: String(localized: "app.update.current_version", table: "App"), currentVersion)
                            alert.informativeText = "\(remoteVersionLine)\n\(currentVersionLine)"
                            alert.addButton(withTitle: String(localized: "app.update.action.download", table: "App"))
                            alert.addButton(withTitle: String(localized: "app.update.action.ignore", table: "App"))
                            let response = alert.runModal()
                            if response == .alertFirstButtonReturn, let url = URL(string: downloadLink) {
                                NSWorkspace.shared.open(url)
                            }
                            completion()
                        }
                    } else {
                        AppLogging.info("Update check completed: trigger=startup, no newer version found, currentVersion=\(currentVersion), remoteVersion=\(remoteVersion).", stage: .app)
                        finishOnMain()
                    }
                } else {
                    AppLogging.error("Update check failed: trigger=startup, invalid update metadata.", stage: .app)
                    finishOnMain()
                }
            } catch {
                AppLogging.error("Update check failed: trigger=startup, details=\(error.localizedDescription).", stage: .app)
                finishOnMain()
            }
        }.resume()
    }
    
}
