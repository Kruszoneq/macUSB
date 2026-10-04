import SwiftUI
import AppKit

struct WelcomeView: View {
    
    // Odbieramy menedżera języka
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var dummyLock: Bool = false
    @State private var isWelcomeVisible = false
    @ObservedObject private var startupCoordinator = WelcomeStartupCoordinator.shared
    @ObservedObject private var menuState = MenuState.shared
    @ObservedObject private var activeOperations = AppActiveOperationRegistry.shared
    @State private var navigateToAnalysis: Bool = false
    @State private var isSupportProjectHovered: Bool = false
    
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
                startupCoordinator.cancelAutomaticNavigation()
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
            startupCoordinator.cancelAutomaticNavigation()
            navigateToAnalysis = true
        }
        .onChange(of: startupCoordinator.canNavigateAutomatically) { _ in
            attemptAutomaticNavigation()
        }
        .onChange(of: menuState.skipWelcomeEnabled) { _ in
            startupCoordinator.refreshPrerequisitesIfNeeded()
            attemptAutomaticNavigation()
        }
        .onChange(of: activeOperations.activeOperationCount) { _ in
            startupCoordinator.refreshPrerequisitesIfNeeded()
            attemptAutomaticNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startupCoordinator.refreshPrerequisitesIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            startupCoordinator.refreshPrerequisitesIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { _ in
            DispatchQueue.main.async { attemptAutomaticNavigation() }
        }
        .onAppear {
            MenuState.shared.resetLanguageChangesForWelcome()
            MenuState.shared.rawLinuxImageSelectionEnabled = true
            isWelcomeVisible = true
            startupCoordinator.setWelcomeActive(true)
            startupCoordinator.startIfNeeded()
            attemptAutomaticNavigation()
        }
        .onDisappear {
            isWelcomeVisible = false
            startupCoordinator.setWelcomeActive(false)
            MenuState.shared.rawLinuxImageSelectionEnabled = false
        }
    }

    private func attemptAutomaticNavigation() {
        guard isWelcomeVisible, !navigateToAnalysis else { return }
        guard startupCoordinator.consumeAutomaticNavigationIfReady() else { return }
        navigateToAnalysis = true
    }
}
