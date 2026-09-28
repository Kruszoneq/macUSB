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

    @inline(__always) private static func appendToBuffer(_ message: String) {
        bufferQueue.async {
            buffer.append(message)
            if buffer.count > bufferMaxLines {
                buffer.removeFirst(buffer.count - bufferMaxLines)
            }
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
