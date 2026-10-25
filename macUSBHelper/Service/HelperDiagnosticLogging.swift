import Foundation
import os.log

enum HelperDiagnosticLogging {
    enum Stage: String {
        case helper = "HELPER"
        case usb = "USB"
    }

    private static let defaultLog = OSLog(subsystem: "com.kruszoneq.macusb.helper", category: "Diagnostics")

    static func info(_ message: String, stage: Stage, log: OSLog? = nil) {
        record(message, stage: stage, log: log ?? defaultLog, type: .default)
    }

    static func error(_ message: String, stage: Stage, log: OSLog? = nil) {
        record(message, stage: stage, log: log ?? defaultLog, type: .error)
    }

    private static func record(_ message: String, stage: Stage, log: OSLog, type: OSLogType) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let prefix = "[\(formatter.string(from: Date()))] [\(stage.rawValue)] [HELPER]"
        for line in message.components(separatedBy: "\n") {
            os_log("%{public}@", log: log, type: type, "\(prefix) \(line)")
        }
    }
}
