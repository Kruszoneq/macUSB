import Foundation
import Combine

@MainActor
final class FinishUSBEjectLogic: ObservableObject {
    enum State: Equatable {
        case ready
        case inProgress
        case ejected
        case unavailable
        case failed
        case debugDisabled
    }

    @Published private(set) var state: State = .unavailable
    @Published private(set) var failureMessage: String?

    private let targetWholeDiskBSDName: String?
    private let isDebugMode: Bool
    private var availabilityTimer: Timer?

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
    }

    func prepareForPresentation() {
        failureMessage = nil

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

        guard state != .inProgress else { return }

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

        failureMessage = nil
        state = .inProgress

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.executeDiskutilEject(for: disk)

            DispatchQueue.main.async {
                if result.exitCode == 0 {
                    AppLogging.info("FinishEject: pomyślnie wysunięto /dev/\(disk).", category: "Installation")
                    self.state = .ejected
                    self.failureMessage = nil
                    return
                }

                if !self.isDiskAvailable(disk) {
                    AppLogging.info("FinishEject: nośnik /dev/\(disk) został odłączony podczas operacji.", category: "Installation")
                    self.state = .unavailable
                    self.failureMessage = nil
                    return
                }

                let stderrText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackMessage = "Zamknij aplikacje używające nośnika i spróbuj ponownie."
                let localizedMessage = String(localized: "finish.eject.error.description")
                let message = stderrText.isEmpty
                    ? (localizedMessage == "finish.eject.error.description" ? fallbackMessage : localizedMessage)
                    : stderrText

                AppLogging.error(
                    "FinishEject: nie udało się wysunąć /dev/\(disk), kod=\(result.exitCode), stderr=\(stderrText)",
                    category: "Installation"
                )

                self.state = .failed
                self.failureMessage = message
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
        case .ready, .failed:
            guard let disk = targetWholeDiskBSDName else {
                state = .unavailable
                failureMessage = nil
                return
            }

            if !isDiskAvailable(disk) {
                AppLogging.info("FinishEject: wykryto odłączenie nośnika /dev/\(disk), dezaktywuję akcję wysuwania.", category: "Installation")
                state = .unavailable
                failureMessage = nil
            }
        case .inProgress, .ejected, .unavailable, .debugDisabled:
            break
        }
    }

    private func isDiskAvailable(_ wholeDiskBSDName: String) -> Bool {
        let devicePath = "/dev/\(wholeDiskBSDName)"
        return FileManager.default.fileExists(atPath: devicePath)
    }

    nonisolated private static func executeDiskutilEject(for wholeDiskBSDName: String) -> (exitCode: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", "/dev/\(wholeDiskBSDName)"]

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
