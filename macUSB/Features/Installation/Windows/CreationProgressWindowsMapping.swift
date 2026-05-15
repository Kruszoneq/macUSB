import Foundation

enum CreationProgressWindowsMapping {
    static let splitWimStageKey = "windows_split_wim"
    static let createStageKey = "windows_create_media"

    static func stageKeys(includeSplitWim: Bool) -> [String] {
        var keys: [String] = [
            "windows_prepare_source",
            "windows_prepare_target",
            "windows_create_media"
        ]

        if includeSplitWim {
            keys.append(splitWimStageKey)
        }

        keys.append("windows_verify_media")
        keys.append("windows_cleanup_temp")
        return keys
    }

    static func pendingIcon(for stageKey: String) -> String? {
        switch stageKey {
        case "windows_prepare_source":
            return "doc.badge.gearshape"
        case "windows_prepare_target":
            return "eject"
        case "windows_create_media":
            return "square.and.arrow.down"
        case "windows_split_wim":
            return "doc.on.doc"
        case "windows_verify_media":
            return "checkmark.seal"
        case "windows_cleanup_temp":
            return "trash"
        default:
            return nil
        }
    }

    static func activeIcon(for stageKey: String) -> String? {
        switch stageKey {
        case "windows_prepare_source":
            return "doc.badge.gearshape.fill"
        case "windows_prepare_target":
            return "eject.fill"
        case "windows_create_media":
            return "square.and.arrow.down.fill"
        case "windows_split_wim":
            return "doc.on.doc.fill"
        case "windows_verify_media":
            return "checkmark.seal.fill"
        case "windows_cleanup_temp":
            return "trash.fill"
        default:
            return nil
        }
    }

    static func showsCopyProgress(for stageKey: String) -> Bool {
        stageKey == createStageKey || stageKey == splitWimStageKey
    }

    static func showsWriteSpeed(for stageKey: String) -> Bool {
        stageKey == createStageKey || stageKey == splitWimStageKey
    }

    static func isTransferStage(_ stageKey: String) -> Bool {
        false
    }

    static func canonicalStageKey(_ stageKey: String) -> String {
        stageKey
    }

    static func stageRange(for stageKey: String) -> (start: Double, end: Double)? {
        switch stageKey {
        case "windows_create_media":
            return (40, 80)
        case "windows_split_wim":
            return (80, 95)
        default:
            return nil
        }
    }

    static func copyPercent(from overallPercent: Double, stageKey: String) -> Double? {
        guard let range = stageRange(for: stageKey), range.end > range.start else {
            return nil
        }

        let clampedOverall = min(max(overallPercent, range.start), range.end)
        let normalized = ((clampedOverall - range.start) / (range.end - range.start)) * 100.0
        return min(max(normalized, 0), 99)
    }
}
