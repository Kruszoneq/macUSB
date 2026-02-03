import Foundation
import OSLog
import Darwin

/// Centralna infrastruktura logowania dla aplikacji macUSB.
///
/// Zasady formatu:
/// - Milestone startu aplikacji:
///   [HH:MM:SS] Start aplikacji
///   ------------
///   Wersja aplikacji: X (Y)
///   Wersja macOS: A.B(.C)
///   Model Maca: MacNN,N
///   ------------
/// - Etapy: `AppLogging.stage("NAZWA ETAPU")` loguje nagłówek z separatorem.
/// - Kroki: `AppLogging.info("komunikat", category: "FileAnalysis")` lub `AppLogging.error(...)`.
/// - Brak RunID — eksport obejmuje pojedynczą sesję.
public enum AppLogging {
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
        let message = """
[\(time)] Start aplikacji
------------
Wersja aplikacji: \(appVer)
Wersja macOS: \(macVer)
Model Maca: \(model)
------------
"""
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

