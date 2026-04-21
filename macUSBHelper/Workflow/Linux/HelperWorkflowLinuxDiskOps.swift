import Foundation

extension HelperWorkflowExecutor {
    func resolveLinuxSourceImageSizeBytes() -> Int64? {
        let sourcePath = request.sourceAppPath
        guard fileManager.fileExists(atPath: sourcePath) else {
            return nil
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: sourcePath),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
    }

    func resolveLinuxTargetWholeDiskName() throws -> String {
        try extractWholeDiskName(from: request.targetBSDName)
    }

    func resolveLinuxRawTargetDevicePath() throws -> String {
        let wholeDisk = try resolveLinuxTargetWholeDiskName()
        return "/dev/r\(wholeDisk)"
    }
}
