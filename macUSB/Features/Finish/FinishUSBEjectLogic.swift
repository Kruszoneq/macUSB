import Foundation
import Combine

@MainActor
final class FinishUSBEjectLogic: ObservableObject {
    enum State: Equatable {
        case ready
        case inProgress
        case forceInProgress
        case ejected
        case unavailable
        case spotlightBlocked
        case failed
        case forceFailed
        case debugDisabled
    }

    @Published private(set) var state: State = .unavailable

    private let targetWholeDiskBSDName: String?
    private let isDebugMode: Bool
    private var availabilityTimer: Timer?
    private var operationToken: AppActiveOperationToken?

    init(targetWholeDiskBSDName: String?, isDebugMode: Bool) {
        if let targetWholeDiskBSDName, !targetWholeDiskBSDName.isEmpty {
            self.targetWholeDiskBSDName = USBDriveLogic.wholeDiskName(from: targetWholeDiskBSDName)
        } else {
            self.targetWholeDiskBSDName = nil
        }
        self.isDebugMode = isDebugMode
    }

    deinit {
        availabilityTimer?.invalidate()
        operationToken?.finish()
    }

    func prepareForPresentation() {
        if isDebugMode {
            state = .debugDisabled
            return
        }

        refreshAvailabilityState()
    }

    func startAvailabilityMonitoring() {
        availabilityTimer?.invalidate()

        availabilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAvailabilityStateIfNeeded()
            }
        }
    }

    func stopAvailabilityMonitoring() {
        availabilityTimer?.invalidate()
        availabilityTimer = nil
    }

    func performEject() {
        guard !isDebugMode else {
            state = .debugDisabled
            return
        }

        guard state != .inProgress, state != .forceInProgress else { return }

        guard let disk = targetWholeDiskBSDName else {
            AppLogging.info("FinishEject: brak identyfikatora whole disk, oznaczam nośnik jako niedostępny.", category: "Installation")
            state = .unavailable
            return
        }

        guard isDiskAvailable(disk) else {
            AppLogging.info("FinishEject: nośnik /dev/\(disk) nie jest już dostępny.", category: "Installation")
            state = .unavailable
            return
        }

        let shouldForceEject = state == .spotlightBlocked || state == .forceFailed
        operationToken?.finish()
        operationToken = AppActiveOperationRegistry.shared.begin(
            kind: .usbEject,
            context: shouldForceEject ? "usb_eject_force:\(disk)" : "usb_eject_standard:\(disk)"
        )
        state = shouldForceEject ? .forceInProgress : .inProgress

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.executeDiskutilEject(for: disk, force: shouldForceEject)

            DispatchQueue.main.async {
                defer {
                    self.operationToken?.finish()
                    self.operationToken = nil
                }
                if result.exitCode == 0 {
                    let mode = shouldForceEject ? "force" : "standard"
                    AppLogging.info("FinishEject: pomyślnie wysunięto /dev/\(disk), tryb=\(mode).", category: "Installation")
                    self.state = .ejected
                    return
                }

                if !self.isDiskAvailable(disk) {
                    AppLogging.info("FinishEject: nośnik /dev/\(disk) został odłączony podczas operacji.", category: "Installation")
                    self.state = .unavailable
                    return
                }

                let stderrText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let isSpotlightDissenter = !shouldForceEject
                    && stderrText.range(of: "mds_stores", options: .caseInsensitive) != nil
                let mode = shouldForceEject ? "force" : "standard"
                let classification = isSpotlightDissenter ? "spotlight_mds_stores" : "generic"

                AppLogging.error(
                    "FinishEject: nie udało się wysunąć /dev/\(disk), tryb=\(mode), klasyfikacja=\(classification), kod=\(result.exitCode), stderr=\(stderrText)",
                    category: "Installation"
                )

                if shouldForceEject {
                    self.state = .forceFailed
                } else if isSpotlightDissenter {
                    self.state = .spotlightBlocked
                } else {
                    self.state = .failed
                }
            }
        }
    }

    private func refreshAvailabilityState() {
        guard !isDebugMode else {
            state = .debugDisabled
            return
        }

        guard let disk = targetWholeDiskBSDName else {
            state = .unavailable
            return
        }

        state = isDiskAvailable(disk) ? .ready : .unavailable
    }

    private func refreshAvailabilityStateIfNeeded() {
        guard !isDebugMode else { return }

        switch state {
        case .ready, .spotlightBlocked, .failed, .forceFailed:
            guard let disk = targetWholeDiskBSDName else {
                state = .unavailable
                return
            }

            if !isDiskAvailable(disk) {
                AppLogging.info("FinishEject: wykryto odłączenie nośnika /dev/\(disk), dezaktywuję akcję wysuwania.", category: "Installation")
                state = .unavailable
            }
        case .inProgress, .forceInProgress, .ejected, .unavailable, .debugDisabled:
            break
        }
    }

    private func isDiskAvailable(_ wholeDiskBSDName: String) -> Bool {
        let devicePath = "/dev/\(wholeDiskBSDName)"
        return FileManager.default.fileExists(atPath: devicePath)
    }

    nonisolated private static func executeDiskutilEject(
        for wholeDiskBSDName: String,
        force: Bool
    ) -> (exitCode: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = force
            ? ["eject", "force", "/dev/\(wholeDiskBSDName)"]
            : ["eject", "/dev/\(wholeDiskBSDName)"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return (1, error.localizedDescription)
        }

        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        return (process.terminationStatus, stderrText)
    }
}
