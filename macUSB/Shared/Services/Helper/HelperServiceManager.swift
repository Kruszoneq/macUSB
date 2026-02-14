import Foundation
import AppKit
import ServiceManagement
import Darwin

final class HelperServiceManager: NSObject {
    static let shared = HelperServiceManager()

    static let daemonPlistName = "com.kruszoneq.macusb.helper.plist"
    static let machServiceName = "com.kruszoneq.macusb.helper"

    private typealias EnsureCompletion = (Bool, String?) -> Void
    private let coordinationQueue = DispatchQueue(label: "macUSB.helper.registration", qos: .userInitiated)
    private var ensureInProgress = false
    private var pendingEnsureCompletions: [EnsureCompletion] = []
    private var pendingEnsureInteractive = false
    private var repairInProgress = false
    private var statusCheckInProgress = false
    private var statusCheckingPanel: NSPanel?
    private var repairProgressPanel: NSPanel?
    private var repairStatusField: NSTextField?
    private var repairLogTextView: NSTextView?
    private var repairSpinner: NSProgressIndicator?
    private var repairCloseButton: NSButton?
    private let repairLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    private let repairSinkLock = NSLock()
    private var repairProgressSink: ((String) -> Void)?
    private let statusHealthTimeout: TimeInterval = 1.6

    private struct HelperStatusSnapshot {
        let isHealthy: Bool
        let detailedText: String
    }

    private override init() {
        super.init()
    }

    func bootstrapIfNeededAtStartup(completion: @escaping (Bool) -> Void) {
        #if DEBUG
        if Self.isRunningFromXcodeDevelopmentBuild() {
            completion(true)
            return
        }
        #endif

        ensureReadyForPrivilegedWork(interactive: false) { ready, _ in
            completion(ready)
        }
    }

    func ensureReadyForPrivilegedWork(completion: @escaping (Bool, String?) -> Void) {
        ensureReadyForPrivilegedWork(interactive: true, completion: completion)
    }

    func presentStatusAlert() {
        coordinationQueue.async {
            guard !self.statusCheckInProgress else {
                return
            }

            self.statusCheckInProgress = true

            DispatchQueue.main.async {
                self.presentStatusCheckingPanelIfNeeded()
            }

            self.evaluateStatus { snapshot in
                DispatchQueue.main.async {
                    self.dismissStatusCheckingPanelIfNeeded()

                    if snapshot.isHealthy {
                        self.presentHealthyStatusAlert(detailsText: snapshot.detailedText)
                    } else {
                        let alert = NSAlert()
                        alert.icon = NSApp.applicationIconImage
                        alert.alertStyle = .informational
                        alert.messageText = String(localized: "Status helpera")
                        alert.informativeText = snapshot.detailedText
                        alert.addButton(withTitle: String(localized: "OK"))
                        self.presentAlert(alert)
                    }

                    self.coordinationQueue.async {
                        self.statusCheckInProgress = false
                    }
                }
            }
        }
    }

    func repairRegistrationFromMenu() {
        guard markRepairStartIfPossible() else { return }
        if Thread.isMainThread {
            startRepairPresentation()
        } else {
            DispatchQueue.main.sync {
                self.startRepairPresentation()
            }
        }
        reportHelperServiceEvent("Rozpoczęto naprawę helpera z menu.")
        PrivilegedOperationClient.shared.resetConnectionForRecovery()
        reportHelperServiceEvent("Zresetowano lokalne połączenie XPC przed naprawą.")

        ensureReadyForPrivilegedWork(interactive: true) { ready, message in
            self.finishRepairFlow()
            let summary = message ?? (ready
                                      ? String(localized: "Naprawa helpera zakończona")
                                      : String(localized: "Naprawa helpera zakończona błędem"))
            self.reportHelperServiceEvent("Naprawa helpera zakończona: \(ready ? "OK" : "BŁĄD"). Szczegóły: \(summary)")
            DispatchQueue.main.async {
                self.finishRepairPresentation(success: ready, message: summary)
            }
        }
    }

    func unregisterFromMenu() {
        coordinationQueue.async {
            if self.ensureInProgress {
                DispatchQueue.main.async {
                    self.presentOperationSummary(
                        success: false,
                        message: String(localized: "Trwa inna operacja helpera. Poczekaj chwilę i spróbuj ponownie.")
                    )
                }
                return
            }

            let service = SMAppService.daemon(plistName: Self.daemonPlistName)

            do {
                if service.status == .notRegistered || service.status == .notFound {
                    DispatchQueue.main.async {
                        self.presentOperationSummary(success: true, message: String(localized: "Helper jest już usunięty"))
                    }
                    return
                }

                try service.unregister()
                DispatchQueue.main.async {
                    self.presentOperationSummary(success: true, message: String(localized: "Helper został usunięty"))
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentOperationSummary(success: false, message: error.localizedDescription)
                }
            }
        }
    }

    private func ensureReadyForPrivilegedWork(interactive: Bool, completion: @escaping (Bool, String?) -> Void) {
        reportHelperServiceEvent("Sprawdzanie warunków startu helpera (interactive=\(interactive ? "TAK" : "NIE")).")
        guard isLocationRequirementSatisfied() else {
            let message = String(localized: "Aby uruchomić helper systemowy, aplikacja musi znajdować się w katalogu Applications.")
            reportHelperServiceEvent("Warunek lokalizacji aplikacji niespełniony.")
            if interactive {
                presentMoveToApplicationsAlert()
            }
            completion(false, message)
            return
        }

        queueEnsureRequest(interactive: interactive, completion: completion)
    }

    private func queueEnsureRequest(interactive: Bool, completion: @escaping EnsureCompletion) {
        coordinationQueue.async {
            self.pendingEnsureCompletions.append(completion)
            self.pendingEnsureInteractive = self.pendingEnsureInteractive || interactive
            self.reportHelperServiceEvent("Dodano żądanie gotowości helpera (interactive=\(interactive ? "TAK" : "NIE")).")

            guard !self.ensureInProgress else {
                AppLogging.info(
                    "Wykryto równoległe żądanie gotowości helpera - dołączam do trwającej operacji.",
                    category: "Installation"
                )
                self.reportHelperServiceEvent("Dołączono do trwającej operacji gotowości helpera.")
                return
            }

            self.ensureInProgress = true
            let runInteractive = self.pendingEnsureInteractive
            self.reportHelperServiceEvent("Rozpoczynam flow gotowości helpera (interactive=\(runInteractive ? "TAK" : "NIE")).")
            self.runEnsureFlow(interactive: runInteractive)
        }
    }

    private func runEnsureFlow(interactive: Bool) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        reportHelperServiceEvent("Aktualny status SMAppService: \(statusDescription(service.status)).")
        switch service.status {
        case .enabled:
            reportHelperServiceEvent("Helper jest oznaczony jako włączony. Weryfikuję health XPC.")
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: true) { ready, message in
                self.finalizeEnsureRequests(ready: ready, message: message)
            }

        case .requiresApproval:
            reportHelperServiceEvent("Helper wymaga zatwierdzenia w Ustawieniach systemowych.")
            if interactive {
                DispatchQueue.main.async {
                    self.presentApprovalRequiredAlert()
                }
            }
            finalizeEnsureRequests(
                ready: false,
                message: String(localized: "Helper wymaga zatwierdzenia w Ustawieniach systemowych.")
            )

        case .notRegistered, .notFound:
            reportHelperServiceEvent("Helper nie jest zarejestrowany. Rozpoczynam rejestrację.")
            registerAndValidate(interactive: interactive) { ready, message in
                self.finalizeEnsureRequests(ready: ready, message: message)
            }

        @unknown default:
            reportHelperServiceEvent("Wykryto nieznany status helpera.")
            finalizeEnsureRequests(ready: false, message: String(localized: "Nieznany status helpera."))
        }
    }

    private func registerAndValidate(interactive: Bool, completion: @escaping EnsureCompletion) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        do {
            reportHelperServiceEvent("Wywołuję SMAppService.register().")
            try service.register()
            reportHelperServiceEvent("SMAppService.register() zakończone bez błędu.")
            handlePostRegistrationStatus(interactive: interactive, completion: completion)
        } catch {
            reportHelperServiceEvent("SMAppService.register() zwróciło błąd: \(error.localizedDescription)")
            if service.status == .enabled {
                AppLogging.info(
                    "register() zwrócił błąd, ale helper jest oznaczony jako enabled. Kontynuuję walidację.",
                    category: "Installation"
                )
                reportHelperServiceEvent("Mimo błędu register() status helpera to enabled. Kontynuuję walidację.")
                handlePostRegistrationStatus(interactive: interactive, completion: completion)
                return
            }

            if isRunningFromXcodeSession() && isOperationNotPermitted(error) {
                AppLogging.error(
                    "Rejestracja helpera z uruchomienia Xcode została zablokowana przez system (Operation not permitted).",
                    category: "Installation"
                )
                PrivilegedOperationClient.shared.queryHealth(withTimeout: 1.2) { ok, details in
                    if ok {
                        self.reportHelperServiceEvent("Health XPC po błędzie register() jest poprawny.")
                        completion(true, nil)
                        return
                    }

                    self.reportHelperServiceEvent("Health XPC po błędzie register() nadal nie działa: \(details)")
                    completion(
                        false,
                        String(localized: "System zablokował rejestrację helpera z uruchomienia Xcode. Uruchom raz aplikację z katalogu Applications, zatwierdź działanie helpera w tle, a następnie wróć do testów w Xcode. Szczegóły XPC: \(details)")
                    )
                }
                return
            }

            DispatchQueue.main.async {
                self.presentRegistrationErrorAlertIfNeeded(error: error, interactive: interactive)
            }
            completion(false, error.localizedDescription)
        }
    }

    private func finalizeEnsureRequests(ready: Bool, message: String?) {
        reportHelperServiceEvent("Flow gotowości helpera zakończony: \(ready ? "OK" : "BŁĄD").")
        coordinationQueue.async {
            let completions = self.pendingEnsureCompletions
            self.pendingEnsureCompletions.removeAll()
            self.pendingEnsureInteractive = false
            self.ensureInProgress = false

            DispatchQueue.main.async {
                completions.forEach { callback in
                    callback(ready, message)
                }
            }
        }
    }

    private func handlePostRegistrationStatus(interactive: Bool, completion: @escaping (Bool, String?) -> Void) {
        let service = SMAppService.daemon(plistName: Self.daemonPlistName)
        reportHelperServiceEvent("Status helpera po rejestracji: \(statusDescription(service.status)).")
        switch service.status {
        case .enabled:
            validateEnabledServiceHealth(interactive: interactive, allowRecovery: false, completion: completion)
        case .requiresApproval:
            reportHelperServiceEvent("Helper po rejestracji wymaga zatwierdzenia użytkownika.")
            if interactive {
                presentApprovalRequiredAlert()
            }
            completion(false, String(localized: "Helper został zarejestrowany, ale wymaga zatwierdzenia przez użytkownika."))
        case .notRegistered, .notFound:
            reportHelperServiceEvent("Po rejestracji helper nadal nie jest aktywny.")
            completion(false, String(localized: "Nie udało się aktywować helpera."))
        @unknown default:
            reportHelperServiceEvent("Nieznany status helpera po rejestracji.")
            completion(false, String(localized: "Nieznany status helpera po rejestracji."))
        }
    }

    private func validateEnabledServiceHealth(
        interactive: Bool,
        allowRecovery: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        reportHelperServiceEvent("Rozpoczynam weryfikację health XPC helpera.")
        PrivilegedOperationClient.shared.queryHealth { ok, details in
            if ok {
                self.reportHelperServiceEvent("Health XPC: OK (\(details)).")
                completion(true, nil)
                return
            }
            self.reportHelperServiceEvent("Health XPC: BŁĄD (\(details)).")

            guard allowRecovery else {
                completion(false, "Helper jest włączony, ale XPC nie odpowiada: \(details)")
                return
            }

            AppLogging.error(
                "Weryfikacja health helpera nieudana: \(details). Próba resetu połączenia XPC.",
                category: "Installation"
            )
            PrivilegedOperationClient.shared.resetConnectionForRecovery()
            self.reportHelperServiceEvent("Zresetowano połączenie XPC. Ponawiam health-check.")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                PrivilegedOperationClient.shared.queryHealth { retryOK, retryDetails in
                    if retryOK {
                        self.reportHelperServiceEvent("Health XPC po resecie: OK (\(retryDetails)).")
                        completion(true, nil)
                        return
                    }
                    self.reportHelperServiceEvent("Health XPC po resecie nadal nie działa: \(retryDetails).")

                    self.recoverRegistrationAfterHealthFailure(
                        interactive: interactive,
                        healthDetails: "\(details). Po resecie XPC: \(retryDetails)",
                        completion: completion
                    )
                }
            }
        }
    }

    private func recoverRegistrationAfterHealthFailure(
        interactive: Bool,
        healthDetails: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        reportHelperServiceEvent("Uruchamiam procedurę odzyskiwania rejestracji helpera.")
        coordinationQueue.async {
            let service = SMAppService.daemon(plistName: Self.daemonPlistName)
            do {
                if service.status == .enabled {
                    self.reportHelperServiceEvent("Helper jest enabled. Wywołuję unregister() przed ponowną rejestracją.")
                    try service.unregister()
                    Thread.sleep(forTimeInterval: 0.25)
                }

                self.reportHelperServiceEvent("Wywołuję register() po odzyskiwaniu.")
                try service.register()
                self.handlePostRegistrationStatus(interactive: interactive) { ready, message in
                    guard ready else {
                        self.reportHelperServiceEvent("Po recover register() helper nadal nie jest gotowy.")
                        completion(false, message)
                        return
                    }

                    PrivilegedOperationClient.shared.queryHealth { recovered, recoveredDetails in
                        if recovered {
                            self.reportHelperServiceEvent("Health XPC po odzyskiwaniu: OK (\(recoveredDetails)).")
                            completion(true, nil)
                        } else {
                            self.reportHelperServiceEvent("Health XPC po odzyskiwaniu nadal nie działa: \(recoveredDetails).")
                            completion(
                                false,
                                "Helper został ponownie zarejestrowany, ale XPC nadal nie działa: \(recoveredDetails). Poprzedni błąd: \(healthDetails)"
                            )
                        }
                    }
                }
            } catch {
                self.reportHelperServiceEvent("Błąd podczas odzyskiwania helpera: \(error.localizedDescription)")
                if service.status == .enabled {
                    AppLogging.info(
                        "Ponowna rejestracja helpera zwróciła błąd, ale status to enabled. Kontynuuję walidację.",
                        category: "Installation"
                    )
                    self.reportHelperServiceEvent("Mimo błędu recover status helpera to enabled. Kontynuuję walidację.")
                    self.handlePostRegistrationStatus(interactive: interactive, completion: completion)
                    return
                }

                if self.isRunningFromXcodeSession() && self.isOperationNotPermitted(error) {
                    PrivilegedOperationClient.shared.queryHealth(withTimeout: 1.2) { ok, details in
                        if ok {
                            self.reportHelperServiceEvent("W sesji Xcode recovery zablokowany, ale helper odpowiada przez XPC.")
                            completion(true, nil)
                            return
                        }

                        self.reportHelperServiceEvent("W sesji Xcode recovery zablokowany i helper nadal nie odpowiada przez XPC.")
                        completion(
                            false,
                            "System zablokował ponowną rejestrację helpera z sesji Xcode. Uruchom aplikację z katalogu /Applications i wykonaj naprawę helpera. Szczegóły XPC: \(details). Poprzedni błąd: \(healthDetails)"
                        )
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.presentRegistrationErrorAlertIfNeeded(error: error, interactive: interactive)
                }
                completion(
                    false,
                    "Helper nie odpowiada przez XPC (\(healthDetails)). Nie udało się ponownie zarejestrować helpera: \(error.localizedDescription)"
                )
            }
        }
    }

    private func evaluateStatus(completion: @escaping (HelperStatusSnapshot) -> Void) {
        let serviceStatus = SMAppService.daemon(plistName: Self.daemonPlistName).status
        let serviceStatusLine = "Status usługi: \(statusDescription(serviceStatus))"
        let serviceHealthy = serviceStatus == .enabled

        let locationLine: String
        let locationHealthy: Bool
        if isAppInstalledInApplications() {
            locationLine = String(localized: "Lokalizacja aplikacji: /Applications (OK)")
            locationHealthy = true
        } else {
            #if DEBUG
            if Self.isRunningFromXcodeDevelopmentBuild() {
                locationLine = String(localized: "Lokalizacja aplikacji: środowisko Xcode (bypass DEBUG)")
                locationHealthy = true
            } else {
                locationLine = String(localized: "Lokalizacja aplikacji: poza /Applications")
                locationHealthy = false
            }
            #else
            locationLine = String(localized: "Lokalizacja aplikacji: poza /Applications")
            locationHealthy = false
            #endif
        }

        PrivilegedOperationClient.shared.queryHealth(withTimeout: statusHealthTimeout) { ok, details in
            let lines: [String] = [
                serviceStatusLine,
                "Mach service: \(Self.machServiceName)",
                locationLine,
                "XPC health: \(ok ? "OK" : "BŁĄD")",
                "Szczegóły: \(details)"
            ]

            let healthy = serviceHealthy && locationHealthy && ok
            completion(
                HelperStatusSnapshot(
                    isHealthy: healthy,
                    detailedText: lines.joined(separator: "\n")
                )
            )
        }
    }

    private func presentHealthyStatusAlert(detailsText: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Status helpera")
        alert.informativeText = String(localized: "Helper działa poprawnie")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Wyświetl szczegóły"))

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertSecondButtonReturn else { return }
                DispatchQueue.main.async {
                    self.presentStatusDetailsAlert(detailsText: detailsText)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                presentStatusDetailsAlert(detailsText: detailsText)
            }
        }
    }

    private func presentStatusDetailsAlert(detailsText: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Status helpera")
        alert.informativeText = detailsText
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }

    private func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return String(localized: "Włączony")
        case .notRegistered:
            return String(localized: "Nie zarejestrowany")
        case .requiresApproval:
            return String(localized: "Wymaga zatwierdzenia")
        case .notFound:
            return String(localized: "Nie znaleziono")
        @unknown default:
            return String(localized: "Nieznany")
        }
    }

    private func isAppInstalledInApplications() -> Bool {
        let bundlePath = Bundle.main.bundleURL.standardized.path
        return bundlePath.hasPrefix("/Applications/")
    }

    private func isLocationRequirementSatisfied() -> Bool {
        if isAppInstalledInApplications() {
            return true
        }
        #if DEBUG
        return Self.isRunningFromXcodeDevelopmentBuild()
        #else
        return false
        #endif
    }

    #if DEBUG
    static func isRunningFromXcodeDevelopmentBuild() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil {
            return true
        }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        let bundlePath = Bundle.main.bundleURL.standardized.path
        return bundlePath.contains("/DerivedData/") && bundlePath.contains("/Build/Products/")
    }
    #endif

    private func presentMoveToApplicationsAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Wymagana lokalizacja /Applications")
        alert.informativeText = String(localized: "Aby używać helpera uprzywilejowanego, przenieś aplikację macUSB do katalogu Applications i uruchom ją ponownie.")
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }

    private func presentApprovalRequiredAlert() {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Wymagane zatwierdzenie helpera")
        alert.informativeText = String(localized: "Helper został zarejestrowany, ale wymaga zatwierdzenia w Ustawieniach systemowych, aby mógł wykonywać operacje uprzywilejowane.")
        alert.addButton(withTitle: String(localized: "Otwórz Ustawienia"))
        alert.addButton(withTitle: String(localized: "Nie teraz"))

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func presentRegistrationErrorAlertIfNeeded(error: Error, interactive: Bool) {
        guard interactive else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Nie udało się zarejestrować helpera")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }

    private func presentStatusCheckingPanelIfNeeded() {
        guard statusCheckingPanel == nil else { return }

        let panelSize = NSSize(width: 320, height: 110)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Status helpera")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovable = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: panelSize))

        let spinner = NSProgressIndicator(frame: NSRect(x: 24, y: 46, width: 20, height: 20))
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        contentView.addSubview(spinner)

        let titleField = NSTextField(labelWithString: String(localized: "Sprawdzanie statusu..."))
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleField.frame = NSRect(x: 56, y: 52, width: 240, height: 20)
        contentView.addSubview(titleField)

        let subtitleField = NSTextField(labelWithString: String(localized: "Proszę czekać"))
        subtitleField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.frame = NSRect(x: 56, y: 30, width: 240, height: 16)
        contentView.addSubview(subtitleField)

        panel.contentView = contentView

        if let ownerWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            let ownerFrame = ownerWindow.frame
            let origin = NSPoint(
                x: ownerFrame.midX - panelSize.width / 2,
                y: ownerFrame.midY - panelSize.height / 2
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        panel.orderFrontRegardless()
        statusCheckingPanel = panel
    }

    private func dismissStatusCheckingPanelIfNeeded() {
        guard let panel = statusCheckingPanel else { return }
        panel.orderOut(nil)
        statusCheckingPanel = nil
    }

    private func markRepairStartIfPossible() -> Bool {
        coordinationQueue.sync {
            if repairInProgress {
                DispatchQueue.main.async {
                    self.presentOperationSummary(
                        success: false,
                        message: String(localized: "Trwa już naprawa helpera. Poczekaj na jej zakończenie.")
                    )
                }
                return false
            }
            repairInProgress = true
            return true
        }
    }

    private func finishRepairFlow() {
        coordinationQueue.async {
            self.repairInProgress = false
        }
        setRepairProgressSink(nil)
    }

    private func reportHelperServiceEvent(_ message: String) {
        AppLogging.info(message, category: "HelperService")
        repairSinkLock.lock()
        let sink = repairProgressSink
        repairSinkLock.unlock()
        sink?(message)
    }

    private func setRepairProgressSink(_ sink: ((String) -> Void)?) {
        repairSinkLock.lock()
        repairProgressSink = sink
        repairSinkLock.unlock()
    }

    private func startRepairPresentation() {
        presentRepairProgressPanelIfNeeded()
        repairLogTextView?.string = ""
        repairSpinner?.isHidden = false
        repairSpinner?.startAnimation(nil)
        repairCloseButton?.isEnabled = false
        updateRepairStatus(text: String(localized: "Trwa naprawa helpera..."), result: nil)
        appendRepairProgressLine("Rozpoczynanie operacji naprawy.")
        setRepairProgressSink { [weak self] message in
            DispatchQueue.main.async {
                self?.updateRepairStatus(text: message, result: nil)
                self?.appendRepairProgressLine(message)
            }
        }
    }

    private func finishRepairPresentation(success: Bool, message: String) {
        updateRepairStatus(
            text: success
            ? String(localized: "Naprawa helpera zakończona pomyślnie.")
            : String(localized: "Naprawa helpera zakończona błędem."),
            result: success
        )
        appendRepairProgressLine(message)
        repairSpinner?.stopAnimation(nil)
        repairSpinner?.isHidden = true
        repairCloseButton?.isEnabled = true
    }

    private func presentRepairProgressPanelIfNeeded() {
        if let panel = repairProgressPanel {
            panel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panelSize = NSSize(width: 620, height: 430)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Naprawa helpera")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: panelSize))

        let iconView = NSImageView(frame: NSRect(x: 22, y: panelSize.height - 68, width: 34, height: 34))
        iconView.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        iconView.contentTintColor = .systemBlue
        contentView.addSubview(iconView)

        let titleField = NSTextField(labelWithString: String(localized: "Naprawa helpera"))
        titleField.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleField.frame = NSRect(x: 66, y: panelSize.height - 62, width: 350, height: 28)
        contentView.addSubview(titleField)

        let subtitleField = NSTextField(labelWithString: String(localized: "Bieżący przebieg operacji"))
        subtitleField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.frame = NSRect(x: 66, y: panelSize.height - 82, width: 420, height: 18)
        contentView.addSubview(subtitleField)

        let statusSpinner = NSProgressIndicator(frame: NSRect(x: 24, y: panelSize.height - 112, width: 18, height: 18))
        statusSpinner.style = .spinning
        statusSpinner.controlSize = .small
        contentView.addSubview(statusSpinner)

        let statusField = NSTextField(labelWithString: String(localized: "Przygotowanie..."))
        statusField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusField.textColor = .secondaryLabelColor
        statusField.frame = NSRect(x: 52, y: panelSize.height - 112, width: 540, height: 18)
        contentView.addSubview(statusField)

        let logContainer = NSBox(frame: NSRect(x: 20, y: 64, width: panelSize.width - 40, height: panelSize.height - 196))
        logContainer.boxType = .custom
        logContainer.cornerRadius = 10
        logContainer.borderColor = NSColor.separatorColor
        logContainer.fillColor = NSColor.windowBackgroundColor
        contentView.addSubview(logContainer)

        let scrollFrame = NSRect(x: 1, y: 1, width: logContainer.frame.width - 2, height: logContainer.frame.height - 2)
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = textView
        logContainer.addSubview(scrollView)

        let closeButton = NSButton(title: String(localized: "Zamknij"), target: self, action: #selector(closeRepairProgressPanel(_:)))
        closeButton.bezelStyle = .rounded
        closeButton.isEnabled = false
        closeButton.frame = NSRect(x: panelSize.width - 116, y: 20, width: 92, height: 30)
        contentView.addSubview(closeButton)

        panel.contentView = contentView

        if let ownerWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            let ownerFrame = ownerWindow.frame
            let origin = NSPoint(
                x: ownerFrame.midX - panelSize.width / 2,
                y: ownerFrame.midY - panelSize.height / 2
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        repairProgressPanel = panel
        repairStatusField = statusField
        repairLogTextView = textView
        repairSpinner = statusSpinner
        repairCloseButton = closeButton

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func appendRepairProgressLine(_ line: String) {
        guard let textView = repairLogTextView else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let timestamp = repairLogFormatter.string(from: Date())
        let renderedLine = "[\(timestamp)] \(trimmed)\n"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        textView.textStorage?.append(NSAttributedString(string: renderedLine, attributes: attributes))
        textView.scrollToEndOfDocument(nil)
    }

    private func updateRepairStatus(text: String, result: Bool?) {
        guard let statusField = repairStatusField else { return }
        statusField.stringValue = text
        switch result {
        case .some(true):
            statusField.textColor = .systemGreen
        case .some(false):
            statusField.textColor = .systemRed
        case .none:
            statusField.textColor = .secondaryLabelColor
        }
    }

    @objc private func closeRepairProgressPanel(_ sender: NSButton) {
        repairProgressPanel?.orderOut(nil)
    }

    private func isOperationNotPermitted(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.code == Int(EPERM) || nsError.code == 1 {
            return true
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("operation not permitted")
    }

    private func isRunningFromXcodeSession() -> Bool {
        #if DEBUG
        return Self.isRunningFromXcodeDevelopmentBuild()
        #else
        return false
        #endif
    }

    private func presentOperationSummary(success: Bool, message: String) {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.alertStyle = success ? .informational : .warning
        alert.messageText = success ? String(localized: "Operacja zakończona") : String(localized: "Operacja nie powiodła się")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        presentAlert(alert)
    }

    private func presentAlert(_ alert: NSAlert) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
