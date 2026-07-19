import Foundation

enum PrivilegedHelperServiceCapabilities {
    static let windowsMacUSBoot = "windows.macusboot.v1"

    static func validatedCapabilities() throws -> [String] {
        _ = try HelperWorkflowWindowsMacUSBootArtifactLoader.load()
        return [windowsMacUSBoot]
    }
}
