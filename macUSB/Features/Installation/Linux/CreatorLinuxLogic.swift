import Foundation

extension UniversalInstallationView {
    var isLinuxWorkflow: Bool {
        linuxFlowContext != nil
    }

    var linuxMountPointURLForCleanup: URL? {
        linuxFlowContext?.mountPointURLForCleanup
    }

    var effectiveMountPointForCreation: URL {
        if let linuxMountPointURLForCleanup {
            return linuxMountPointURLForCleanup
        }

        if isLinuxWorkflow {
            return FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_linux_no_mount")
        }

        return sourceAppURL.deletingLastPathComponent()
    }

    var shouldDetachMountPointAfterFinish: Bool {
        if isLinuxWorkflow {
            return linuxMountPointURLForCleanup != nil
        }
        return true
    }

    func performEmergencyCleanupIfNeeded(tempURL: URL) {
        if let mountPoint = linuxMountPointURLForCleanup {
            performEmergencyCleanup(mountPoint: mountPoint, tempURL: tempURL)
            return
        }

        if isLinuxWorkflow {
            log("Cleanup Linux: pomijam odmontowanie obrazu (brak aktywnego mounted image path).")
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            return
        }

        performEmergencyCleanup(mountPoint: sourceAppURL.deletingLastPathComponent(), tempURL: tempURL)
    }

}
