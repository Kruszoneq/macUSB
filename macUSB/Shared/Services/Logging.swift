import Foundation
import OSLog
import Darwin

/// Central logging infrastructure for macUSB.
///
/// App diagnostics use the stage format
/// in `docs/reference/platform/LOGGING_CONTRACT.md`.
public enum AppLogging {
    public enum Stage: String {
        case app = "APP"
        case permissions = "PERMISSIONS"
        case helper = "HELPER"
        case analysis = "ANALYSIS"
        case usb = "USB"
        case downloader = "DOWNLOADER"
    }

    public enum Workflow: String {
        case macos = "MACOS"
        case sierra = "SIERRA"
        case catalina = "CATALINA"
        case legacyRestore = "LEGACYRESTORE"
        case mavericks = "MAVERICKS"
        case windows = "WINDOWS"
        case linux = "LINUX"
        case ppc = "PPC"
        case raw = "RAW"
        case discovery = "DISCOVERY"
        case modern = "MODERN"
        case legacy = "LEGACY"
        case oldest = "OLDEST"
        case repair = "REPAIR"
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "macUSB"
    private static let appLogger = Logger(subsystem: subsystem, category: "App")
    private static var didLogStartup: Bool = false

    private static let bufferQueue = DispatchQueue(label: "macUSB.LoggingBuffer")
    private static var buffer: [String] = []
    private static let bufferMaxLines: Int = 10000
    private static var currentSessionURL: URL?
    private static var previousSessionURL: URL?
    private static var currentSessionHandle: FileHandle?
    private static var previousSessionAvailable = false

    /// Starts a new log session and makes the immediately preceding session available for export.
    public static func startSession() {
        bufferQueue.sync {
            guard currentSessionURL == nil else { return }
            do {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(subsystem, isDirectory: true)
                    .appendingPathComponent("DiagnosticLogs", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )

                let current = directory.appendingPathComponent("current-session.log")
                let previous = directory.appendingPathComponent("previous-session.log")
                if FileManager.default.fileExists(atPath: current.path) {
                    let data = try Data(contentsOf: current)
                    if data.isEmpty {
                        try? FileManager.default.removeItem(at: previous)
                    } else {
                        try data.write(to: previous, options: .atomic)
                        try FileManager.default.setAttributes(
                            [.posixPermissions: 0o600],
                            ofItemAtPath: previous.path
                        )
                        previousSessionAvailable = true
                    }
                    try FileManager.default.removeItem(at: current)
                } else {
                    try? FileManager.default.removeItem(at: previous)
                }

                guard FileManager.default.createFile(
                    atPath: current.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                currentSessionHandle = try FileHandle(forWritingTo: current)
                currentSessionURL = current
                previousSessionURL = previous
            } catch {
                appLogger.error("Failed to initialize diagnostic log storage: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public static var hasPreviousSessionLogs: Bool {
        bufferQueue.sync { previousSessionAvailable }
    }

    public static func previousSessionLogText() throws -> String {
        try bufferQueue.sync {
            guard previousSessionAvailable, let previousSessionURL else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let data = try Data(contentsOf: previousSessionURL)
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// Appends the final termination result and flushes the bounded export buffer.
    public static func finishSession(cleanupSucceeded: Bool) {
        bufferQueue.sync {
            guard let currentSessionURL else { return }
            let separator = formattedLine("------------", label: Stage.app.rawValue, helperOrigin: false)
            let result = formattedLine(
                cleanupSucceeded
                    ? "Application terminated successfully."
                    : "Application terminated with cleanup errors.",
                label: Stage.app.rawValue,
                helperOrigin: false
            )
            let logger = Logger(subsystem: subsystem, category: Stage.app.rawValue)
            logger.info("\(separator, privacy: .public)")
            if cleanupSucceeded {
                logger.info("\(result, privacy: .public)")
            } else {
                logger.error("\(result, privacy: .public)")
            }
            buffer.append(contentsOf: [separator, result])
            if buffer.count > bufferMaxLines {
                buffer.removeFirst(buffer.count - bufferMaxLines)
            }
            persist(separator)
            persist(result)
            try? currentSessionHandle?.close()
            currentSessionHandle = nil
            do {
                let data = Data(buffer.joined(separator: "\n").utf8)
                try data.write(to: currentSessionURL, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: currentSessionURL.path
                )
            } catch {
                appLogger.error("Failed to finalize diagnostic log storage: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @inline(__always) private static func appendToBuffer(_ message: String) {
        bufferQueue.async {
            buffer.append(message)
            if buffer.count > bufferMaxLines {
                buffer.removeFirst(buffer.count - bufferMaxLines)
            }
            persist(message)
        }
    }

    public static func prepareExportedLogText() -> String {
        let marker = formattedLine("Diagnostic log generated for export.", label: Stage.app.rawValue, helperOrigin: false)
        appLogger.info("\(marker, privacy: .public)")
        var snapshot: [String] = []
        bufferQueue.sync {
            buffer.append(marker)
            if buffer.count > bufferMaxLines {
                buffer.removeFirst(buffer.count - bufferMaxLines)
            }
            persist(marker)
            snapshot = buffer
        }
        return snapshot.joined(separator: "\n")
    }

    /// Jednorazowy log startowy po uruchomieniu aplikacji.
    public static func logAppStartupOnce() {
        guard !didLogStartup else { return }
        didLogStartup = true
        let time = currentTimeString()
        let appVer = appVersionString()
        let macVer = macOSVersionString()
        let model = hardwareModelString()
        let architecture = MacHardwareArchitecture.current.diagnosticLabel
        let prefix = "[\(time)] [APP]"
        let message = [
            "\(prefix) ┌─ macUSB session started",
            "\(prefix) │ App version   : \(appVer)",
            "\(prefix) │ macOS version : \(macVer)",
            "\(prefix) │ Mac model     : \(model)",
            "\(prefix) │ Architecture  : \(architecture)",
            "\(prefix) └────────────────────────────────────"
        ].joined(separator: "\n")
        appLogger.info("\(message, privacy: .public)")
        appendToBuffer(message)
    }

    /// Logs a migrated diagnostic line with the operation stage after the timestamp.
    public static func info(_ message: String, stage: Stage, workflow: Workflow? = nil, helperOrigin: Bool = false) {
        let label = stageLabel(stage, workflow: workflow)
        let line = formattedLine(message, label: label, helperOrigin: helperOrigin)
        let logger = Logger(subsystem: subsystem, category: label)
        logger.info("\(line, privacy: .public)")
        appendToBuffer(line)
    }

    public static func error(_ message: String, stage: Stage, workflow: Workflow? = nil, helperOrigin: Bool = false) {
        let label = stageLabel(stage, workflow: workflow)
        let line = formattedLine(message, label: label, helperOrigin: helperOrigin)
        let logger = Logger(subsystem: subsystem, category: label)
        logger.error("\(line, privacy: .public)")
        appendToBuffer(line)
    }

    public static func separator(stage: Stage, workflow: Workflow? = nil) {
        info("------------", stage: stage, workflow: workflow)
    }
}

// MARK: - Prywatne helpery
private extension AppLogging {
    static func persist(_ message: String) {
        guard let currentSessionHandle else { return }
        do {
            try currentSessionHandle.write(contentsOf: Data((message + "\n").utf8))
        } catch {
            appLogger.error("Failed to append diagnostic log: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func formattedLine(_ message: String, label: String, helperOrigin: Bool) -> String {
        let prefix = "[\(currentTimeString())] [\(label)]\(helperOrigin ? " [HELPER]" : "")"
        return message.components(separatedBy: "\n")
            .map { "\(prefix) \($0)" }
            .joined(separator: "\n")
    }

    static func stageLabel(_ stage: Stage, workflow: Workflow?) -> String {
        guard let workflow else { return stage.rawValue }
        return "\(stage.rawValue)_\(workflow.rawValue)"
    }

    static func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    static func appVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func macOSVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.patchVersion > 0 {
            return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        } else {
            return "\(v.majorVersion).\(v.minorVersion)"
        }
    }

    static func hardwareModelString() -> String {
        if let model = sysctlString(for: "hw.model"), !model.isEmpty { return model }
        return "Unknown"
    }

    static func sysctlString(for name: String) -> String? {
        var size: size_t = 0
        if sysctlbyname(name, nil, &size, nil, 0) != 0 { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        if sysctlbyname(name, &buffer, &size, nil, 0) != 0 { return nil }
        return String(cString: buffer)
    }
}
