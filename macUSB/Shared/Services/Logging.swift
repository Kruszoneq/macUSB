import Foundation
import OSLog
import Darwin

/// Central logging infrastructure for macUSB.
///
/// The startup block uses English labels and prefixes every line with `[HH:MM:SS] [APP]`.
/// Other logging paths are being migrated to the contract in
/// `docs/reference/platform/LOGGING_CONTRACT.md` in stages.
public enum AppLogging {
    public enum Stage: String {
        case permissions = "PERMISSIONS"
        case helper = "HELPER"
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "macUSB"
    private static let appLogger = Logger(subsystem: subsystem, category: "App")
    private static var didLogStartup: Bool = false

    private static let bufferQueue = DispatchQueue(label: "macUSB.LoggingBuffer")
    private static var buffer: [String] = []
    private static let bufferMaxLines: Int = 5000

    @inline(__always) private static func appendToBuffer(_ message: String) {
        bufferQueue.async {
            buffer.append(message)
            if buffer.count > bufferMaxLines {
                buffer.removeFirst(buffer.count - bufferMaxLines)
            }
        }
    }

    /// Zwraca sklejone logi z bufora w formie tekstu.
    public static func exportedLogText() -> String {
        var snapshot: [String] = []
        bufferQueue.sync { snapshot = buffer }
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

    /// Loguje nagłówek etapu w spójnym stylu.
    public static func stage(_ title: String) {
        let time = currentTimeString()
        let message = """
------------
[\(time)] \(title)
------------
"""
        appLogger.info("\(message, privacy: .public)")
        appendToBuffer(message)
    }

    /// Loguje prosty separator w logach.
    public static func separator() {
        let message = "------------"
        appLogger.info("\(message, privacy: .public)")
        appendToBuffer(message)
    }

    /// Log informacji dla danej kategorii (jednowierszowy, z godziną).
    public static func info(_ message: String, category: String = "General") {
        let t = currentTimeString()
        let line = "[\(t)][\(category)] \(message)"
        let logger = Logger(subsystem: subsystem, category: category)
        logger.info("\(line, privacy: .public)")
        appendToBuffer(line)
    }

    /// Log błędu dla danej kategorii (jednowierszowy, z godziną).
    public static func error(_ message: String, category: String = "General") {
        let t = currentTimeString()
        let line = "[\(t)][\(category)][ERROR] \(message)"
        let logger = Logger(subsystem: subsystem, category: category)
        logger.error("\(line, privacy: .public)")
        appendToBuffer(line)
    }

    /// Logs a migrated diagnostic line with the operation stage after the timestamp.
    public static func info(_ message: String, stage: Stage) {
        let line = "[\(currentTimeString())] [\(stage.rawValue)] \(message)"
        let logger = Logger(subsystem: subsystem, category: stage.rawValue)
        logger.info("\(line, privacy: .public)")
        appendToBuffer(line)
    }

    public static func error(_ message: String, stage: Stage) {
        let line = "[\(currentTimeString())] [\(stage.rawValue)] \(message)"
        let logger = Logger(subsystem: subsystem, category: stage.rawValue)
        logger.error("\(line, privacy: .public)")
        appendToBuffer(line)
    }
}

// MARK: - Prywatne helpery
private extension AppLogging {
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
