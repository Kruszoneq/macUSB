import AppKit

@MainActor
final class AppWindowCloseGuard: NSObject, NSWindowDelegate {
    static let shared = AppWindowCloseGuard()

    private weak var guardedWindow: NSWindow?
    private var beforeAllowedClose: (() -> Void)?

    private override init() {}

    func install(on window: NSWindow) {
        guardedWindow = window
        window.delegate = self
    }

    func setBeforeAllowedClose(_ action: (() -> Void)?) {
        beforeAllowedClose = action
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === guardedWindow else { return true }
        guard AppTerminationCoordinator.shared.shouldAllowWindowClose() else { return false }
        beforeAllowedClose?()
        return true
    }
}
