import Foundation
import Darwin

enum HelperWorkflowWindowsMacUSBootSynchronizationMode {
    case full
    case fsyncOnly(unsupportedFullSyncErrno: Int32)

    var diagnosticDescription: String {
        switch self {
        case .full:
            return "mode=fsync+F_FULLFSYNC"
        case .fsyncOnly(let code):
            return "mode=fsync-only, F_FULLFSYNC=unsupported, errno=\(code), message=\(String(cString: strerror(code)))"
        }
    }
}

final class HelperWorkflowWindowsMacUSBootRawDevice {
    private static let getBlockSizeRequest = UInt(0x40046418)
    private static let getBlockCountRequest = UInt(0x40086419)

    let path: String
    let blockSize: UInt32
    let blockCount: UInt64
    private var descriptor: Int32

    init(path: String) throws {
        self.path = path

        var fileStatus = stat()
        guard lstat(path, &fileStatus) == 0,
              (fileStatus.st_mode & S_IFMT) == S_IFCHR else {
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess("raw target is not a character device: \(path)")
        }

        let openedDescriptor = Darwin.open(path, O_RDWR | O_EXLOCK | O_CLOEXEC)
        guard openedDescriptor >= 0 else {
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess(
                "open failed path=\(path), errno=\(errno), message=\(String(cString: strerror(errno)))"
            )
        }
        descriptor = openedDescriptor

        var resolvedBlockSize: UInt32 = 0
        guard ioctl(openedDescriptor, Self.getBlockSizeRequest, &resolvedBlockSize) == 0 else {
            let detail = "DKIOCGETBLOCKSIZE failed errno=\(errno)"
            Darwin.close(openedDescriptor)
            descriptor = -1
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess(detail)
        }

        var resolvedBlockCount: UInt64 = 0
        guard ioctl(openedDescriptor, Self.getBlockCountRequest, &resolvedBlockCount) == 0 else {
            let detail = "DKIOCGETBLOCKCOUNT failed errno=\(errno)"
            Darwin.close(openedDescriptor)
            descriptor = -1
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess(detail)
        }

        blockSize = resolvedBlockSize
        blockCount = resolvedBlockCount
    }

    deinit {
        _ = close()
    }

    @discardableResult
    func close() -> Bool {
        guard descriptor >= 0 else { return true }
        let result = Darwin.close(descriptor)
        descriptor = -1
        return result == 0
    }

    func read(offset: UInt64, count: Int) throws -> Data {
        guard descriptor >= 0, count >= 0 else {
            throw posixError(operation: "read", code: EBADF)
        }
        var data = Data(count: count)
        var failureCode: Int32?

        let bytesRead = data.withUnsafeMutableBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            var total = 0
            while total < count {
                let result = pread(
                    descriptor,
                    baseAddress.advanced(by: total),
                    count - total,
                    off_t(offset + UInt64(total))
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    failureCode = errno
                    return total
                }
                if result == 0 { return total }
                total += result
            }
            return total
        }

        if let failureCode {
            throw posixError(operation: "read", code: failureCode)
        }
        guard bytesRead == count else {
            throw posixError(operation: "read short", code: EIO)
        }
        return data
    }

    func write(_ data: Data, offset: UInt64) throws {
        guard descriptor >= 0 else {
            throw posixError(operation: "write", code: EBADF)
        }
        var failureCode: Int32?

        let bytesWritten = data.withUnsafeBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            var total = 0
            while total < data.count {
                let result = pwrite(
                    descriptor,
                    baseAddress.advanced(by: total),
                    data.count - total,
                    off_t(offset + UInt64(total))
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    failureCode = errno
                    return total
                }
                if result == 0 { return total }
                total += result
            }
            return total
        }

        if let failureCode {
            throw posixError(operation: "write", code: failureCode)
        }
        guard bytesWritten == data.count else {
            throw posixError(operation: "write short", code: EIO)
        }
    }

    func synchronize() throws -> HelperWorkflowWindowsMacUSBootSynchronizationMode {
        guard descriptor >= 0 else {
            throw posixError(operation: "synchronize", code: EBADF)
        }
        guard fsync(descriptor) == 0 else {
            throw posixError(operation: "fsync", code: errno)
        }

        if fcntl(descriptor, F_FULLFSYNC) == 0 {
            return .full
        }

        let fullSyncError = errno
        if fullSyncError == ENOTTY || fullSyncError == ENOTSUP {
            return .fsyncOnly(unsupportedFullSyncErrno: fullSyncError)
        }
        throw posixError(operation: "F_FULLFSYNC", code: fullSyncError)
    }

    private func posixError(operation: String, code: Int32) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(operation) failed errno=\(code), message=\(String(cString: strerror(code)))"]
        )
    }
}
