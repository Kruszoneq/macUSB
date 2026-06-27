import Foundation
import os.log

enum HelperConnectionSecurityPolicy {
    private static let teamIdentifier = "27NC66L8P2"

    #if DEBUG
    static let expectedClientBundleIdentifier = "com.kruszoneq.macUSB.debug"
    #else
    static let expectedClientBundleIdentifier = "com.kruszoneq.macUSB"
    #endif

    static let trustedClientRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier \"\(expectedClientBundleIdentifier)\""

    private static let trustLog = OSLog(subsystem: "com.kruszoneq.macusb.helper", category: "XPCTrust")

    static func configure(_ listener: NSXPCListener, machServiceName: String) {
        os_log(
            "Configuring XPC client trust requirement: machService=%{public}@ expectedClientBundleID=%{public}@",
            log: trustLog,
            type: .default,
            machServiceName,
            expectedClientBundleIdentifier
        )

        listener.setConnectionCodeSigningRequirement(trustedClientRequirement)

        os_log(
            "XPC client trust requirement configured: machService=%{public}@ status=OK",
            log: trustLog,
            type: .default,
            machServiceName
        )
    }

    static func logAcceptedConnection(_ connection: NSXPCConnection) {
        os_log(
            "Accepted XPC connection prevalidated by code signing requirement: pid=%{public}d euid=%{public}d expectedClientBundleID=%{public}@",
            log: trustLog,
            type: .default,
            connection.processIdentifier,
            connection.effectiveUserIdentifier,
            expectedClientBundleIdentifier
        )
    }
}
