import Foundation

struct HelperWorkflowStageLocalization {
    let titleKey: String
    let statusKey: String
}

enum HelperWorkflowLocalizationKeys {
    static let prepareSourceTitle = "helper.workflow.prepare_source.title"
    static let prepareSourceStatus = "helper.workflow.prepare_source.status"

    static let preformatTitle = "helper.workflow.preformat.title"
    static let preformatStatus = "helper.workflow.preformat.status"

    static let imagescanTitle = "helper.workflow.imagescan.title"
    static let imagescanStatus = "helper.workflow.imagescan.status"

    static let restoreTitle = "helper.workflow.restore.title"
    static let restoreStatus = "helper.workflow.restore.status"

    static let ppcFormatTitle = "helper.workflow.ppc_format.title"
    static let ppcFormatStatus = "helper.workflow.ppc_format.status"

    static let ppcRestoreTitle = "helper.workflow.ppc_restore.title"
    static let ppcRestoreStatus = "helper.workflow.ppc_restore.status"

    static let createinstallmediaTitle = "helper.workflow.createinstallmedia.title"
    static let createinstallmediaStatus = "helper.workflow.createinstallmedia.status"
    static let linuxUnmountTargetTitle = "helper.workflow.linux_unmount_target.title"
    static let linuxUnmountTargetStatus = "helper.workflow.linux_unmount_target.status"
    static let linuxRawCopyTitle = "helper.workflow.linux_raw_copy.title"
    static let linuxRawCopyStatus = "helper.workflow.linux_raw_copy.status"
    static let linuxVerifyWriteTitle = "helper.workflow.linux_verify_write.title"
    static let linuxVerifyWriteStatus = "helper.workflow.linux_verify_write.status"
    static let windowsPrepareSourceTitle = "helper.workflow.windows_prepare_source.title"
    static let windowsPrepareSourceStatus = "helper.workflow.windows_prepare_source.status"
    static let windowsPrepareTargetTitle = "helper.workflow.windows_prepare_target.title"
    static let windowsPrepareTargetStatus = "helper.workflow.windows_prepare_target.status"
    static let windowsCreateMediaTitle = "helper.workflow.windows_create_media.title"
    static let windowsCreateMediaStatus = "helper.workflow.windows_create_media.status"
    static let windowsSplitWimTitle = "helper.workflow.windows_split_wim.title"
    static let windowsSplitWimStatus = "helper.workflow.windows_split_wim.status"
    static let windowsVerifyMediaTitle = "helper.workflow.windows_verify_media.title"
    static let windowsVerifyMediaStatus = "helper.workflow.windows_verify_media.status"
    static let windowsCleanupTempTitle = "helper.workflow.windows_cleanup_temp.title"
    static let windowsCleanupTempStatus = "helper.workflow.windows_cleanup_temp.status"
    static let startingTitle = "helper.workflow.starting.title"
    static let startingStatus = "helper.workflow.starting.status"
    static let initializingStatus = "helper.workflow.initializing.status"

    static let catalinaCleanupTitle = "helper.workflow.catalina_cleanup.title"
    static let catalinaCleanupStatus = "helper.workflow.catalina_cleanup.status"
    static let catalinaCopyTitle = "helper.workflow.catalina_copy.title"
    static let catalinaCopyStatus = "helper.workflow.catalina_copy.status"
    static let catalinaXattrTitle = "helper.workflow.catalina_xattr.title"
    static let catalinaXattrStatus = "helper.workflow.catalina_xattr.status"

    static let cleanupTempTitle = "helper.workflow.cleanup_temp.title"
    static let cleanupTempStatus = "helper.workflow.cleanup_temp.status"

    static let finalizeTitle = "helper.workflow.finalize.title"
    static let finalizeStatus = "helper.workflow.finalize.status"

    static func presentation(for stageKey: String) -> HelperWorkflowStageLocalization? {
        switch stageKey {
        case "prepare_source":
            return HelperWorkflowStageLocalization(titleKey: prepareSourceTitle, statusKey: prepareSourceStatus)
        case "preformat":
            return HelperWorkflowStageLocalization(titleKey: preformatTitle, statusKey: preformatStatus)
        case "imagescan":
            return HelperWorkflowStageLocalization(titleKey: imagescanTitle, statusKey: imagescanStatus)
        case "restore":
            return HelperWorkflowStageLocalization(titleKey: restoreTitle, statusKey: restoreStatus)
        case "ppc_format":
            return HelperWorkflowStageLocalization(titleKey: ppcFormatTitle, statusKey: ppcFormatStatus)
        case "ppc_restore":
            return HelperWorkflowStageLocalization(titleKey: ppcRestoreTitle, statusKey: ppcRestoreStatus)
        case "createinstallmedia":
            return HelperWorkflowStageLocalization(titleKey: createinstallmediaTitle, statusKey: createinstallmediaStatus)
        case "linux_unmount_target":
            return HelperWorkflowStageLocalization(titleKey: linuxUnmountTargetTitle, statusKey: linuxUnmountTargetStatus)
        case "linux_raw_copy":
            return HelperWorkflowStageLocalization(titleKey: linuxRawCopyTitle, statusKey: linuxRawCopyStatus)
        case "linux_verify_write":
            return HelperWorkflowStageLocalization(titleKey: linuxVerifyWriteTitle, statusKey: linuxVerifyWriteStatus)
        case "windows_prepare_source":
            return HelperWorkflowStageLocalization(titleKey: windowsPrepareSourceTitle, statusKey: windowsPrepareSourceStatus)
        case "windows_prepare_target":
            return HelperWorkflowStageLocalization(titleKey: windowsPrepareTargetTitle, statusKey: windowsPrepareTargetStatus)
        case "windows_create_media":
            return HelperWorkflowStageLocalization(titleKey: windowsCreateMediaTitle, statusKey: windowsCreateMediaStatus)
        case "windows_split_wim":
            return HelperWorkflowStageLocalization(titleKey: windowsSplitWimTitle, statusKey: windowsSplitWimStatus)
        case "windows_verify_media":
            return HelperWorkflowStageLocalization(titleKey: windowsVerifyMediaTitle, statusKey: windowsVerifyMediaStatus)
        case "windows_cleanup_temp":
            return HelperWorkflowStageLocalization(titleKey: windowsCleanupTempTitle, statusKey: windowsCleanupTempStatus)
        case "catalina_cleanup":
            return HelperWorkflowStageLocalization(titleKey: catalinaCleanupTitle, statusKey: catalinaCleanupStatus)
        case "catalina_copy":
            return HelperWorkflowStageLocalization(titleKey: catalinaCopyTitle, statusKey: catalinaCopyStatus)
        case "catalina_xattr":
            return HelperWorkflowStageLocalization(titleKey: catalinaXattrTitle, statusKey: catalinaXattrStatus)
        case "cleanup_temp":
            return HelperWorkflowStageLocalization(titleKey: cleanupTempTitle, statusKey: cleanupTempStatus)
        case "finalize":
            return HelperWorkflowStageLocalization(titleKey: finalizeTitle, statusKey: finalizeStatus)
        default:
            return nil
        }
    }
}

enum HelperWorkflowLocalizationExtractionAnchors {
    // Keep literal keys here so String Catalog extraction can detect dynamic helper keys used at runtime.
    static let anchoredValues: [String] = [
        String(localized: "helper.workflow.prepare_source.title"),
        String(localized: "helper.workflow.prepare_source.status"),
        String(localized: "helper.workflow.preformat.title"),
        String(localized: "helper.workflow.preformat.status"),
        String(localized: "helper.workflow.imagescan.title"),
        String(localized: "helper.workflow.imagescan.status"),
        String(localized: "helper.workflow.restore.title"),
        String(localized: "helper.workflow.restore.status"),
        String(localized: "helper.workflow.ppc_format.title"),
        String(localized: "helper.workflow.ppc_format.status"),
        String(localized: "helper.workflow.ppc_restore.title"),
        String(localized: "helper.workflow.ppc_restore.status"),
        String(localized: "helper.workflow.createinstallmedia.title"),
        String(localized: "helper.workflow.createinstallmedia.status"),
        String(localized: "helper.workflow.linux_unmount_target.title"),
        String(localized: "helper.workflow.linux_unmount_target.status"),
        String(localized: "helper.workflow.linux_raw_copy.title"),
        String(localized: "helper.workflow.linux_raw_copy.status"),
        String(localized: "helper.workflow.linux_verify_write.title"),
        String(localized: "helper.workflow.linux_verify_write.status"),
        String(localized: "helper.workflow.windows_prepare_source.title"),
        String(localized: "helper.workflow.windows_prepare_source.status"),
        String(localized: "helper.workflow.windows_prepare_target.title"),
        String(localized: "helper.workflow.windows_prepare_target.status"),
        String(localized: "helper.workflow.windows_create_media.title"),
        String(localized: "helper.workflow.windows_create_media.status"),
        String(localized: "helper.workflow.windows_split_wim.title"),
        String(localized: "helper.workflow.windows_split_wim.status"),
        String(localized: "helper.workflow.windows_verify_media.title"),
        String(localized: "helper.workflow.windows_verify_media.status"),
        String(localized: "helper.workflow.windows_cleanup_temp.title"),
        String(localized: "helper.workflow.windows_cleanup_temp.status"),
        String(localized: "helper.workflow.starting.title"),
        String(localized: "helper.workflow.starting.status"),
        String(localized: "helper.workflow.initializing.status"),
        String(localized: "helper.workflow.catalina_cleanup.title"),
        String(localized: "helper.workflow.catalina_cleanup.status"),
        String(localized: "helper.workflow.catalina_copy.title"),
        String(localized: "helper.workflow.catalina_copy.status"),
        String(localized: "helper.workflow.catalina_xattr.title"),
        String(localized: "helper.workflow.catalina_xattr.status"),
        String(localized: "helper.workflow.cleanup_temp.title"),
        String(localized: "helper.workflow.cleanup_temp.status"),
        String(localized: "helper.workflow.finalize.title"),
        String(localized: "helper.workflow.finalize.status")
    ]
}
