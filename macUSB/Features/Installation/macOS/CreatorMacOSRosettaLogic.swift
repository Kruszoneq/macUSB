import AppKit
import Foundation

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
            && effectiveMacOSRosettaState != .available
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
        alert.messageText = String(localized: "installation.summary.rosetta.license.title")
        alert.informativeText = String(localized: "installation.summary.rosetta.license.description")
        alert.addButton(withTitle: String(localized: "installation.summary.rosetta.license.agree"))
        alert.addButton(withTitle: String(localized: "installation.summary.rosetta.license.disagree"))

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else {
                AppLogging.info("Użytkownik nie zaakceptował umowy licencyjnej Rosetty.", category: "Rosetta")
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
        macOSRosettaState = .installing
        macOSRosettaRetryGeneration = UUID()
        AppLogging.info("Rozpoczynam przygotowanie helpera do instalacji Rosetty.", category: "Rosetta")

        HelperServiceManager.shared.ensureReadyForPrivilegedWork { ready, failureReason in
            guard ready else {
                macOSRosettaState = .installFailed
                AppLogging.error(
                    "Helper nie jest gotowy do instalacji Rosetty: \(failureReason ?? "brak szczegółów")",
                    category: "Rosetta"
                )
                return
            }

            PrivilegedOperationClient.shared.installRosetta { result in
                switch result {
                case .success(let payload):
                    AppLogging.info(
                        "Helper zakończył instalację Rosetty: success=\(payload.success), status=\(payload.terminationStatus), details=\(payload.diagnosticMessage ?? "brak")",
                        category: "Rosetta"
                    )
                    guard payload.success else {
                        macOSRosettaState = .installFailed
                        return
                    }
                    runMacOSRosettaPostInstallChecks(attempt: 1)

                case .failure(let error):
                    macOSRosettaState = .installFailed
                    AppLogging.error(
                        "Instalacja Rosetty przez helper nie powiodła się: \(error.localizedDescription)",
                        category: "Rosetta"
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
                    "Sprawdzenie Rosetty po instalacji: próba \(attempt)/5, wynik=\(availability.diagnosticLabel)",
                    category: "Rosetta"
                )

                if availability == .available {
                    macOSRosettaState = .available
                    macOSRosettaRetryGeneration = nil
                    return
                }

                guard attempt < 5 else {
                    macOSRosettaState = .notAvailable
                    macOSRosettaRetryGeneration = nil
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    runMacOSRosettaPostInstallChecks(attempt: attempt + 1)
                }
            }
        }
    }

    func checkMacOSRosettaAvailabilityManually() {
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
                    "Ręczne sprawdzenie Rosetty: \(availability.diagnosticLabel)",
                    category: "Rosetta"
                )
            }
        }
    }

    func invalidateMacOSRosettaChecks() {
        macOSRosettaRetryGeneration = nil
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
