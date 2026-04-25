import Foundation
import AppKit
import ServiceManagement
import Darwin

final class HelperServiceManager: NSObject {
    static let shared = HelperServiceManager()

    #if DEBUG
    static let daemonPlistName = "com.kruszoneq.macusb.helper.debug.plist"
    static let machServiceName = "com.kruszoneq.macusb.helper.debug"
    #else
    static let daemonPlistName = "com.kruszoneq.macusb.helper.plist"
    static let machServiceName = "com.kruszoneq.macusb.helper"
    #endif
    static let helperRepairFingerprintDefaultsKey = "macUSB.Helper.LastSuccessfulAutoRepairFingerprint"

    typealias EnsureCompletion = (Bool, String?) -> Void
    let coordinationQueue = DispatchQueue(label: "macUSB.helper.registration", qos: .userInitiated)
    var ensureInProgress = false
    var pendingEnsureCompletions: [EnsureCompletion] = []
    var pendingEnsureInteractive = false
    var repairInProgress = false
    var statusCheckInProgress = false
    var statusCheckingPanel: NSPanel?
    var repairProgressPanel: NSPanel?
    var repairPresentationModel: HelperRepairPanelPresentationModel?
    weak var repairProgressAlertParentWindow: NSWindow?
    var repairProgressAlertWindow: NSWindow?
    var repairTechnicalLogs: [String] = []
    weak var statusCheckAlertParentWindow: NSWindow?
    var statusCheckAlertWindow: NSWindow?
    var didPresentStartupApprovalPrompt = false
    let repairLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    let repairSinkLock = NSLock()
    var repairProgressSink: ((String) -> Void)?
    let statusHealthTimeout: TimeInterval = 1.6

    struct HelperStatusSnapshot {
        let isHealthy: Bool
        let serviceStatus: SMAppService.Status
        let detailedText: String
    }

    private override init() {
        super.init()
    }
}
