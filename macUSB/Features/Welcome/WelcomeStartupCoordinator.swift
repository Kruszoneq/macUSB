import Foundation
import AppKit
import Combine

/// Owns startup for the app session, independently of SwiftUI view recreation.
final class WelcomeStartupCoordinator: ObservableObject {
    static let shared = WelcomeStartupCoordinator()

    @Published private(set) var canNavigateAutomatically = false
    private(set) var isWelcomeActive = false

    private var welcomeVisibilityGeneration = 0

    private var didStart = false
    private var didFinish = false
    private var didLeaveWelcome = false
    private var helperStartupAllowsAutomaticNavigation = false
    private var updateResult: WelcomeStartupUpdateResult?
    private var isRefreshingPrerequisites = false
    private let updateChecker = WelcomeStartupUpdateChecker()

    private init() {}

    func setWelcomeActive(_ active: Bool) {
        guard isWelcomeActive != active else { return }
        isWelcomeActive = active
        welcomeVisibilityGeneration += 1
        canNavigateAutomatically = false
        if active {
            refreshPrerequisitesIfNeeded()
        }
    }

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        FullDiskAccessPermissionManager.shared.handleStartupPromptIfNeeded {
            HelperServiceManager.shared.bootstrapIfNeededAtStartup { helperResult in
                DispatchQueue.main.async {
                    self.helperStartupAllowsAutomaticNavigation = helperResult.isReady && !helperResult.requiredAutoRepair
                    NotificationPermissionManager.shared.handleStartupFlowIfNeeded()
                    self.updateChecker.check { result in
                        self.updateResult = result
                        self.didFinish = true
                        if !self.helperStartupAllowsAutomaticNavigation || result != .upToDate {
                            AppLogging.info(
                                "Automatic welcome transition blocked: helperBootstrapSucceeded=\(helperResult.isReady), " +
                                "helperAutoRepairRequired=\(helperResult.requiredAutoRepair), updateCheck=\(result.rawValue).",
                                stage: .app
                            )
                        }
                        self.refreshPrerequisitesIfNeeded()
                    }
                }
            }
        }
    }

    func refreshPrerequisitesIfNeeded() {
        guard isWelcomeActive, MenuState.shared.skipWelcomeEnabled,
              didFinish, !didLeaveWelcome, helperStartupAllowsAutomaticNavigation,
              updateResult == .upToDate, !isRefreshingPrerequisites else { return }
        isRefreshingPrerequisites = true
        let visibilityGeneration = welcomeVisibilityGeneration
        canNavigateAutomatically = false
        // Recheck after the network request and after returning from System Settings.
        FullDiskAccessPermissionManager.shared.refreshState(trigger: .startup) { access in
            HelperServiceManager.shared.evaluatePassiveReadiness { snapshot in
                DispatchQueue.main.async {
                    self.isRefreshingPrerequisites = false
                    guard self.isWelcomeActive, !self.didLeaveWelcome else { return }
                    guard visibilityGeneration == self.welcomeVisibilityGeneration else {
                        self.refreshPrerequisitesIfNeeded()
                        return
                    }
                    let ready = access.hasConfirmedAccess && snapshot.state == .ready
                    AppLogging.info(
                        "Automatic welcome transition prerequisites checked: fullDiskAccess=\(access.rawValue), helper=\(snapshot.state.rawValue).",
                        stage: .app
                    )
                    self.canNavigateAutomatically = ready
                }
            }
        }
    }

    func consumeAutomaticNavigationIfReady() -> Bool {
        guard isWelcomeActive, canNavigateAutomatically, !didLeaveWelcome,
              helperStartupAllowsAutomaticNavigation,
              MenuState.shared.skipWelcomeEnabled,
              MenuState.shared.hasFullDiskAccess,
              !MenuState.shared.helperRequiresBackgroundApproval,
              !AppActiveOperationRegistry.shared.hasActiveOperations,
              NSApp.isActive, NSApp.modalWindow == nil,
              !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else { return false }
        didLeaveWelcome = true
        AppLogging.info(
            "Automatically moving from the welcome screen to analysis: startup checks completed successfully.",
            stage: .app
        )
        return true
    }

    func cancelAutomaticNavigation() {
        didLeaveWelcome = true
        canNavigateAutomatically = false
    }
}
