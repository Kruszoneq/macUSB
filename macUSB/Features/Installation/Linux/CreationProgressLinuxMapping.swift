import Foundation

enum CreationProgressLinuxMapping {
    static let stageKeys: [String] = [
        "prepare_source",
        "linux_unmount_target",
        "linux_raw_copy",
        "cleanup_temp"
    ]

    static func pendingIcon(for stageKey: String) -> String? {
        switch stageKey {
        case "linux_unmount_target":
            return "eject"
        case "linux_raw_copy":
            return "square.and.arrow.down"
        default:
            return nil
        }
    }

    static func activeIcon(for stageKey: String) -> String? {
        switch stageKey {
        case "linux_unmount_target":
            return "eject.fill"
        case "linux_raw_copy":
            return "square.and.arrow.down.fill"
        default:
            return nil
        }
    }

    static func showsWriteSpeed(for stageKey: String) -> Bool {
        stageKey == "linux_raw_copy"
    }

    static func showsCopyProgress(for stageKey: String) -> Bool {
        stageKey == "linux_raw_copy"
    }

    static func isTransferStage(_ stageKey: String) -> Bool {
        stageKey == "linux_raw_copy"
    }

    static func canonicalStageKey(_ stageKey: String) -> String {
        switch stageKey {
        case "linux_dd_raw_copy":
            return "linux_raw_copy"
        default:
            return stageKey
        }
    }
}
