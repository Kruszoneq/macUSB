import AppKit
import Foundation
import SwiftUI

enum CreatorMacOSRosettaState: Equatable {
    case available
    case missing
    case installing
    case checking
    case checkFailed
    case installFailed
    case notAvailable
}

extension UniversalInstallationView {
    var effectiveMacOSRosettaState: CreatorMacOSRosettaState {
        if let macOSRosettaState {
            return macOSRosettaState
        }

        switch macOSRosettaRequirement.initialAvailability {
        case .available:
            return .available
        case .missing:
            return .missing
        case .indeterminate:
            return .checkFailed
        case nil:
            return .available
        }
    }

    var macOSRosettaShouldShowCard: Bool {
        macOSRosettaRequirement.initialAvailability != nil
            && (effectiveMacOSRosettaState != .available || macOSRosettaSuccessVisible)
    }

    var macOSRosettaShouldBlockStart: Bool {
        macOSRosettaRequirement.initialAvailability != nil
            && effectiveMacOSRosettaState != .available
    }

    var macOSRosettaIsBusy: Bool {
        effectiveMacOSRosettaState == .installing || effectiveMacOSRosettaState == .checking
    }

    func initializeMacOSRosettaStateIfNeeded() {
        guard macOSRosettaState == nil else { return }
        macOSRosettaState = effectiveMacOSRosettaState
    }

    func performMacOSRosettaPrimaryAction() {
        switch effectiveMacOSRosettaState {
        case .missing, .installFailed:
            presentMacOSRosettaLicenseAlert()
        case .checkFailed, .notAvailable:
            checkMacOSRosettaAvailabilityManually()
        case .available, .installing, .checking:
            break
        }
    }

    func presentMacOSRosettaLicenseAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "summary.macos.rosetta.license.title", table: "Summary")
        alert.informativeText = String(localized: "summary.macos.rosetta.license.description", table: "Summary")
        alert.addButton(withTitle: String(localized: "summary.macos.rosetta.license.agree", table: "Summary"))
        alert.addButton(withTitle: String(localized: "summary.macos.rosetta.license.disagree", table: "Summary"))

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else {
                AppLogging.info("User declined the Rosetta license agreement.", stage: .usb, workflow: creationLogWorkflow)
                return
            }
            startMacOSRosettaInstallation()
        }

        if let window = hostingWindow ?? NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    func startMacOSRosettaInstallation() {
        beginMacOSRosettaOperation(context: "installation")
        macOSRosettaState = .installing
        macOSRosettaRetryGeneration = UUID()
        AppLogging.info("Preparing the helper for Rosetta installation.", stage: .usb, workflow: creationLogWorkflow)

        HelperServiceManager.shared.ensureReadyForPrivilegedWork { ready, failureReason in
            guard ready else {
                macOSRosettaState = .installFailed
                finishMacOSRosettaOperation()
                AppLogging.error(
                    "Helper is not ready for Rosetta installation: \(failureReason ?? "no details")",
                    stage: .usb,
                    workflow: creationLogWorkflow
                )
                return
            }

            PrivilegedOperationClient.shared.installRosetta { result in
                switch result {
                case .success(let payload):
                    AppLogging.info(
                        "Rosetta installation helper finished: success=\(payload.success), status=\(payload.terminationStatus), details=\(payload.diagnosticMessage ?? "none")",
                        stage: .usb,
                        workflow: creationLogWorkflow,
                        helperOrigin: true
                    )
                    guard payload.success else {
                        macOSRosettaState = .installFailed
                        finishMacOSRosettaOperation()
                        return
                    }
                    runMacOSRosettaPostInstallChecks(attempt: 1)

                case .failure(let error):
                    macOSRosettaState = .installFailed
                    finishMacOSRosettaOperation()
                    AppLogging.error(
                        "Rosetta installation through the helper failed: \(error.localizedDescription)",
                        stage: .usb,
                        workflow: creationLogWorkflow
                    )
                }
            }
        }
    }

    func runMacOSRosettaPostInstallChecks(attempt: Int) {
        let generation = macOSRosettaRetryGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            let availability = RosettaAvailabilityProbe.check()
            DispatchQueue.main.async {
                guard generation == macOSRosettaRetryGeneration else { return }

                AppLogging.info(
                    "Rosetta post-install check: attempt=\(attempt)/5, result=\(availability.diagnosticLabel)",
                    stage: .usb,
                    workflow: creationLogWorkflow
                )

                if availability == .available {
                    macOSRosettaRetryGeneration = nil
                    showMacOSRosettaInstallationSuccess()
                    finishMacOSRosettaOperation()
                    return
                }

                guard attempt < 5 else {
                    macOSRosettaState = .notAvailable
                    macOSRosettaRetryGeneration = nil
                    finishMacOSRosettaOperation()
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    runMacOSRosettaPostInstallChecks(attempt: attempt + 1)
                }
            }
        }
    }

    func checkMacOSRosettaAvailabilityManually() {
        beginMacOSRosettaOperation(context: "manual_check")
        macOSRosettaState = .checking
        let generation = UUID()
        macOSRosettaRetryGeneration = generation

        DispatchQueue.global(qos: .userInitiated).async {
            let availability = RosettaAvailabilityProbe.check()
            DispatchQueue.main.async {
                guard generation == macOSRosettaRetryGeneration else { return }
                macOSRosettaRetryGeneration = nil

                switch availability {
                case .available:
                    macOSRosettaState = .available
                case .missing:
                    macOSRosettaState = .notAvailable
                case .indeterminate:
                    macOSRosettaState = .checkFailed
                }
                AppLogging.info(
                    "Manual Rosetta availability check: \(availability.diagnosticLabel)",
                    stage: .usb,
                    workflow: creationLogWorkflow
                )
                finishMacOSRosettaOperation()
            }
        }
    }

    func invalidateMacOSRosettaChecks() {
        macOSRosettaRetryGeneration = nil
        macOSRosettaSuccessDismissalGeneration = nil
        if effectiveMacOSRosettaState == .checking {
            finishMacOSRosettaOperation()
        }
    }

    private func showMacOSRosettaInstallationSuccess() {
        let generation = UUID()
        macOSRosettaSuccessDismissalGeneration = generation

        withAnimation(.easeInOut(duration: 0.24)) {
            macOSRosettaState = .available
            macOSRosettaSuccessVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard generation == macOSRosettaSuccessDismissalGeneration else { return }
            macOSRosettaSuccessDismissalGeneration = nil

            withAnimation(.easeInOut(duration: 0.24)) {
                macOSRosettaSuccessVisible = false
            }
        }
    }

    private func beginMacOSRosettaOperation(context: String) {
        macOSRosettaOperationToken?.finish()
        macOSRosettaOperationToken = AppActiveOperationRegistry.shared.begin(
            kind: .rosettaInstallation,
            context: "rosetta:\(context)"
        )
    }

    private func finishMacOSRosettaOperation() {
        macOSRosettaOperationToken?.finish()
        macOSRosettaOperationToken = nil
    }
}

private extension RosettaAvailability {
    var diagnosticLabel: String {
        switch self {
        case .available:
            return "dostępna"
        case .missing:
            return "niezainstalowana"
        case .indeterminate:
            return "stan niejednoznaczny"
        }
    }
}
