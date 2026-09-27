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
    private let loggingWorkflow: AppLogging.Workflow
    private var availabilityTimer: Timer?
    private var operationToken: AppActiveOperationToken?

    init(targetWholeDiskBSDName: String?, isDebugMode: Bool, loggingWorkflow: AppLogging.Workflow) {
        if let targetWholeDiskBSDName, !targetWholeDiskBSDName.isEmpty {
            self.targetWholeDiskBSDName = USBDriveLogic.wholeDiskName(from: targetWholeDiskBSDName)
        } else {
            self.targetWholeDiskBSDName = nil
        }
        self.isDebugMode = isDebugMode
        self.loggingWorkflow = loggingWorkflow
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
            AppLogging.info("Eject unavailable: whole-disk identifier is missing.", stage: .usb, workflow: loggingWorkflow)
            state = .unavailable
            return
        }

        guard isDiskAvailable(disk) else {
            AppLogging.info("Eject unavailable: /dev/\(disk) is no longer present.", stage: .usb, workflow: loggingWorkflow)
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
                    AppLogging.info("Ejected /dev/\(disk) successfully: mode=\(mode).", stage: .usb, workflow: self.loggingWorkflow)
                    self.state = .ejected
                    return
                }

                if !self.isDiskAvailable(disk) {
                    AppLogging.info("Eject target /dev/\(disk) disconnected during the operation.", stage: .usb, workflow: self.loggingWorkflow)
                    self.state = .unavailable
                    return
                }

                let stderrText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let isSpotlightDissenter = !shouldForceEject
                    && stderrText.range(of: "mds_stores", options: .caseInsensitive) != nil
                let mode = shouldForceEject ? "force" : "standard"
                let classification = isSpotlightDissenter ? "spotlight_mds_stores" : "generic"

                AppLogging.error(
                    "Eject failed: disk=/dev/\(disk), mode=\(mode), classification=\(classification), exitCode=\(result.exitCode), stderr=\(stderrText)",
                    stage: .usb,
                    workflow: self.loggingWorkflow
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
                AppLogging.info("Eject target /dev/\(disk) disconnected; disabling the eject action.", stage: .usb, workflow: loggingWorkflow)
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
