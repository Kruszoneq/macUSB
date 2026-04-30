import Foundation
import DiskArbitration

final class HelperWorkflowLinuxMountGuard {
    private let targetWholeDisk: String
    private let log: (String) -> Void
    private let callbackQueue = DispatchQueue(label: "macUSB.helper.linux.mountguard")

    private var session: DASession?
    private var callbackContext: UnsafeMutableRawPointer?
    private var blockedMountAttempts: Int = 0
    private var isStarted = false

    init(targetWholeDisk: String, log: @escaping (String) -> Void) {
        self.targetWholeDisk = targetWholeDisk
        self.log = log
    }

    func start() throws {
        guard !isStarted else { return }
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw NSError(
                domain: "macUSBHelper",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Nie udało się utworzyć sesji Disk Arbitration dla blokady auto-mount Linux."]
            )
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        DASessionSetDispatchQueue(session, callbackQueue)
        DARegisterDiskMountApprovalCallback(
            session,
            nil,
            helperWorkflowLinuxMountApprovalCallback,
            context
        )

        self.session = session
        self.callbackContext = context
        self.isStarted = true

        log("Linux mount guard: start target=\(targetWholeDisk)")
    }

    func stop(reason: String) {
        guard isStarted else { return }

        if let session, let callbackContext {
            DAUnregisterCallback(
                session,
                unsafeBitCast(helperWorkflowLinuxMountApprovalCallback as DADiskMountApprovalCallback, to: UnsafeMutableRawPointer.self),
                callbackContext
            )
            DASessionSetDispatchQueue(session, nil)
        }

        session = nil
        callbackContext = nil
        isStarted = false

        log("Linux mount guard: release reason=\(reason), blocked_attempts=\(blockedMountAttempts)")
    }

    func markVerifyWindowActive() {
        log("Linux mount guard: verification window active (auto-mount blocked)")
    }

    fileprivate func approveOrDenyMount(for disk: DADisk) -> Unmanaged<DADissenter>? {
        guard let diskBSDName = resolveDiskBSDName(disk),
              matchesTargetDiskOrPartition(diskBSDName) else {
            return nil
        }

        blockedMountAttempts += 1
        log("Linux mount guard: blocked auto-mount for \(diskBSDName) (attempt=\(blockedMountAttempts))")

        let dissenter = DADissenterCreate(
            kCFAllocatorDefault,
            DAReturn(kDAReturnExclusiveAccess),
            "macUSB Linux verification in progress" as CFString
        )
        return Unmanaged.passRetained(dissenter)
    }

    private func resolveDiskBSDName(_ disk: DADisk) -> String? {
        guard let cString = DADiskGetBSDName(disk) else {
            return nil
        }
        return String(cString: cString)
    }

    private func matchesTargetDiskOrPartition(_ bsdName: String) -> Bool {
        if bsdName == targetWholeDisk {
            return true
        }
        guard bsdName.hasPrefix(targetWholeDisk) else {
            return false
        }
        let suffix = bsdName.dropFirst(targetWholeDisk.count)
        return suffix.hasPrefix("s")
    }
}

private func helperWorkflowLinuxMountApprovalCallback(
    _ disk: DADisk,
    _ context: UnsafeMutableRawPointer?
) -> Unmanaged<DADissenter>? {
    guard let context else {
        return nil
    }

    let guardInstance = Unmanaged<HelperWorkflowLinuxMountGuard>
        .fromOpaque(context)
        .takeUnretainedValue()
    return guardInstance.approveOrDenyMount(for: disk)
}
