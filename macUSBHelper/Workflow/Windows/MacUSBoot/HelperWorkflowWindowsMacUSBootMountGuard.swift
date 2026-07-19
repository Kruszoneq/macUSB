import Foundation
import DiskArbitration

final class HelperWorkflowWindowsMacUSBootMountGuard {
    private let targetWholeDisk: String
    private let log: (String) -> Void
    private let callbackQueue = DispatchQueue(label: "macUSB.helper.windows.macusboot.mountguard")

    private var session: DASession?
    private var callbackContext: UnsafeMutableRawPointer?
    private var blockedMountAttempts = 0
    private var isStarted = false

    init(targetWholeDisk: String, log: @escaping (String) -> Void) {
        self.targetWholeDisk = targetWholeDisk
        self.log = log
    }

    func start() throws {
        guard !isStarted else { return }
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess("cannot create Disk Arbitration session")
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        DASessionSetDispatchQueue(session, callbackQueue)
        DARegisterDiskMountApprovalCallback(
            session,
            nil,
            helperWorkflowWindowsMacUSBootMountApprovalCallback,
            context
        )

        self.session = session
        callbackContext = context
        isStarted = true
        log("macUSBoot mount guard started: target=\(targetWholeDisk)")
    }

    func stop(reason: String) {
        guard isStarted else { return }
        if let session, let callbackContext {
            DAUnregisterCallback(
                session,
                unsafeBitCast(
                    helperWorkflowWindowsMacUSBootMountApprovalCallback as DADiskMountApprovalCallback,
                    to: UnsafeMutableRawPointer.self
                ),
                callbackContext
            )
            DASessionSetDispatchQueue(session, nil)
        }

        session = nil
        callbackContext = nil
        isStarted = false
        log("macUSBoot mount guard released: reason=\(reason), blockedAttempts=\(blockedMountAttempts)")
    }

    fileprivate func approveOrDenyMount(for disk: DADisk) -> Unmanaged<DADissenter>? {
        guard let cString = DADiskGetBSDName(disk) else { return nil }
        let bsdName = String(cString: cString)
        guard bsdName == targetWholeDisk || bsdName.hasPrefix(targetWholeDisk + "s") else {
            return nil
        }

        blockedMountAttempts += 1
        log("macUSBoot mount guard blocked auto-mount: device=\(bsdName), attempt=\(blockedMountAttempts)")
        let dissenter = DADissenterCreate(
            kCFAllocatorDefault,
            DAReturn(kDAReturnExclusiveAccess),
            "macUSB macUSBoot installation in progress" as CFString
        )
        return Unmanaged.passRetained(dissenter)
    }
}

private func helperWorkflowWindowsMacUSBootMountApprovalCallback(
    _ disk: DADisk,
    _ context: UnsafeMutableRawPointer?
) -> Unmanaged<DADissenter>? {
    guard let context else { return nil }
    return Unmanaged<HelperWorkflowWindowsMacUSBootMountGuard>
        .fromOpaque(context)
        .takeUnretainedValue()
        .approveOrDenyMount(for: disk)
}
