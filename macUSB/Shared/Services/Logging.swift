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

    public static var diagnosticLogsDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(subsystem, isDirectory: true)
            .appendingPathComponent("DiagnosticLogs", isDirectory: true)
    }

    private static let bufferQueue = DispatchQueue(label: "macUSB.LoggingBuffer")
    private static var buffer: [String] = []
    private static let bufferMaxLines: Int = 10000
    private static var currentSessionURL: URL?
    private static var previousSessionURL: URL?
    private static var currentSessionHandle: FileHandle?

    /// Starts a new log session and makes the immediately preceding session available for export.
    public static func startSession() {
        let startedAt = Date()
        bufferQueue.sync {
            guard currentSessionURL == nil else { return }
            do {
                let directory = diagnosticLogsDirectoryURL
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                let existing = try sessionLogFiles(in: directory)
                previousSessionURL = existing.filter { $0.size > 0 }
                    .max { lhs, rhs in
                        if lhs.modifiedAt == rhs.modifiedAt {
                            if lhs.createdAt != rhs.createdAt {
                                return lhs.createdAt < rhs.createdAt
                            }
                            if lhs.url.lastPathComponent == "current-session.log" { return false }
                            if rhs.url.lastPathComponent == "current-session.log" { return true }
                            return lhs.url.lastPathComponent < rhs.url.lastPathComponent
                        }
                        return lhs.modifiedAt < rhs.modifiedAt
                    }?.url

                let (current, handle) = try createSessionLog(in: directory, startedAt: startedAt)
                currentSessionURL = current
                currentSessionHandle = handle

                if let previous = previousSessionURL, isLegacySessionLog(previous) {
                    do {
                        previousSessionURL = try migrateLegacySessionLog(previous, into: directory)
                    } catch {
                        appLogger.error("Failed to rename the previous diagnostic log: \(error.localizedDescription, privacy: .public)")
                    }
                }

                for file in existing where file.url != previousSessionURL {
                    guard FileManager.default.fileExists(atPath: file.url.path) else { continue }
                    do {
                        try FileManager.default.removeItem(at: file.url)
                    } catch {
                        appLogger.error("Failed to remove an older diagnostic log: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } catch {
                appLogger.error("Failed to initialize diagnostic log storage: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public static var hasPreviousSessionLogs: Bool {
        bufferQueue.sync { previousSessionURL != nil }
    }

    public static func exportPreviousSession(to destination: URL) throws {
        let (source, current) = try bufferQueue.sync { () throws -> (URL, URL?) in
            guard let previousSessionURL else { throw CocoaError(.fileReadNoSuchFile) }
            return (previousSessionURL, currentSessionURL)
        }
        guard destination.standardizedFileURL != current?.standardizedFileURL,
              destination.standardizedFileURL != source.standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }

        let fileManager = FileManager.default
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".macUSB-log-export-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: source, to: temporary)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    /// Appends the final termination result and closes the session file without rewriting it.
    public static func finishSession(cleanupSucceeded: Bool) {
        bufferQueue.sync {
            guard currentSessionHandle != nil else { return }
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
    struct SessionLogFile {
        let url: URL
        let size: Int
        let modifiedAt: Date
        let createdAt: Date
    }

    static func sessionLogFiles(in directory: URL) throws -> [SessionLogFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey
        ]
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            guard isManagedSessionLog(url),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return SessionLogFile(
                url: url,
                size: values.fileSize ?? 0,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                createdAt: values.creationDate ?? .distantPast
            )
        }
    }

    static func isManagedSessionLog(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name == "current-session.log" || name == "previous-session.log" { return true }
        return name.range(
            of: #"^log-[0-9]{6}-[0-9]{6}(-[0-9]+)?\.log$"#,
            options: .regularExpression
        ) != nil
    }

    static func isLegacySessionLog(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name == "current-session.log" || name == "previous-session.log"
    }

    static func sessionLogURL(in directory: URL, startedAt: Date, attempt: Int) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyMMdd-HHmmss"
        let suffix = attempt == 1 ? "" : "-\(attempt)"
        return directory.appendingPathComponent("log-\(formatter.string(from: startedAt))\(suffix).log")
    }

    static func createSessionLog(in directory: URL, startedAt: Date) throws -> (URL, FileHandle) {
        for attempt in 1...1000 {
            let url = sessionLogURL(in: directory, startedAt: startedAt, attempt: attempt)
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
            if descriptor >= 0 {
                return (url, FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
            }
            if errno != EEXIST {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    static func migrateLegacySessionLog(_ source: URL, into directory: URL) throws -> URL {
        let startedAt = (try? source.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        for attempt in 1...1000 {
            let destination = sessionLogURL(in: directory, startedAt: startedAt, attempt: attempt)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        throw CocoaError(.fileWriteFileExists)
    }

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
