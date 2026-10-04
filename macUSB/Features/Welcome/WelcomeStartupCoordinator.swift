import Foundation
import AppKit
import Combine

/// Owns startup for the app session, independently of SwiftUI view recreation.
final class WelcomeStartupCoordinator: ObservableObject {
    static let shared = WelcomeStartupCoordinator()

    @Published private(set) var canNavigateAutomatically = false

    private var didStart = false
    private var didFinish = false
    private var didLeaveWelcome = false
    private var helperBootstrapSucceeded = false
    private var updateResult: WelcomeStartupUpdateResult?
    private var isRefreshingPrerequisites = false
    private let updateChecker = WelcomeStartupUpdateChecker()

    private init() {}

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        FullDiskAccessPermissionManager.shared.handleStartupPromptIfNeeded {
            HelperServiceManager.shared.bootstrapIfNeededAtStartup { helperReady in
                DispatchQueue.main.async {
                    self.helperBootstrapSucceeded = helperReady
                    NotificationPermissionManager.shared.handleStartupFlowIfNeeded()
                    self.updateChecker.check { result in
                        self.updateResult = result
                        self.didFinish = true
                        if !helperReady || result != .upToDate {
                            AppLogging.info(
                                "Automatic welcome transition blocked: helperBootstrapSucceeded=\(helperReady), updateCheck=\(result.rawValue).",
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
        guard MenuState.shared.skipWelcomeEnabled,
              didFinish, !didLeaveWelcome, helperBootstrapSucceeded,
              updateResult == .upToDate, !isRefreshingPrerequisites else { return }
        isRefreshingPrerequisites = true
        canNavigateAutomatically = false
        // Recheck after the network request and after returning from System Settings.
        FullDiskAccessPermissionManager.shared.refreshState(trigger: .startup) { access in
            HelperServiceManager.shared.evaluatePassiveReadiness { snapshot in
                DispatchQueue.main.async {
                    self.isRefreshingPrerequisites = false
                    guard !self.didLeaveWelcome else { return }
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
        guard canNavigateAutomatically, !didLeaveWelcome,
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
