import Foundation

struct LinuxInstallationFlowContext {
    let sourceImageURL: URL
    let mountedImagePath: String?

    var sourcePath: String {
        sourceImageURL.path
    }

    var mountPointURLForCleanup: URL? {
        guard let mountedImagePath, mountedImagePath.hasPrefix("/Volumes/") else {
            return nil
        }
        return URL(fileURLWithPath: mountedImagePath)
    }
}
