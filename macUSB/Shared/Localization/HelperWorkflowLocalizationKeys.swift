import Foundation

struct HelperWorkflowStageLocalization {
    let titleKey: String
    let statusKey: String
}

enum HelperWorkflowLocalizationKeys {
    static let prepareSourceTitle = "creator.workflow.prepare_source.title"
    static let prepareSourceStatus = "creator.workflow.prepare_source.status"

    static let preformatTitle = "creator.macos.workflow.preformat.title"
    static let preformatStatus = "creator.macos.workflow.preformat.status"

    static let imagescanTitle = "creator.macos.workflow.imagescan.title"
    static let imagescanStatus = "creator.macos.workflow.imagescan.status"

    static let restoreTitle = "creator.macos.workflow.restore.title"
    static let restoreStatus = "creator.macos.workflow.restore.status"

    static let ppcFormatTitle = "creator.macos.workflow.ppc_format.title"
    static let ppcFormatStatus = "creator.macos.workflow.ppc_format.status"

    static let ppcRestoreTitle = "creator.macos.workflow.ppc_restore.title"
    static let ppcRestoreStatus = "creator.macos.workflow.ppc_restore.status"

    static let createinstallmediaTitle = "creator.macos.workflow.createinstallmedia.title"
    static let createinstallmediaStatus = "creator.macos.workflow.createinstallmedia.status"
    static let linuxUnmountTargetTitle = "creator.workflow.unmount_target.title"
    static let linuxUnmountTargetStatus = "creator.workflow.unmount_target.status"
    static let linuxRawCopyTitle = "creator.linux.workflow.raw_copy.title"
    static let linuxRawCopyStatus = "creator.linux.workflow.raw_copy.status"
    static let linuxVerifyWriteTitle = "creator.linux.workflow.verify_write.title"
    static let linuxVerifyWriteStatus = "creator.linux.workflow.verify_write.status"
    static let windowsPrepareSourceTitle = "creator.windows.workflow.prepare_source.title"
    static let windowsPrepareSourceStatus = "creator.windows.workflow.prepare_source.status"
    static let windowsPrepareTargetTitle = "creator.windows.workflow.prepare_target.title"
    static let windowsPrepareTargetStatus = "creator.windows.workflow.prepare_target.status"
    static let windowsCreateMediaTitle = "creator.windows.workflow.create_media.title"
    static let windowsCreateMediaStatus = "creator.windows.workflow.create_media.status"
    static let windowsSplitWimTitle = "creator.windows.workflow.split_wim.title"
    static let windowsSplitWimStatus = "creator.windows.workflow.split_wim.status"
    static let windowsCreateAutounattendTitle = "creator.windows.workflow.create_autounattend.title"
    static let windowsCreateAutounattendStatus = "creator.windows.workflow.create_autounattend.status"
    static let windowsVerifyMediaTitle = "creator.windows.workflow.verify_media.title"
    static let windowsVerifyMediaStatus = "creator.windows.workflow.verify_media.status"
    static let windowsInstallMacUSBootTitle = "creator.windows.workflow.install_macusboot.title"
    static let windowsInstallMacUSBootCheckingArtifact = "creator.windows.workflow.install_macusboot.checking_artifact"
    static let windowsInstallMacUSBootUnmounting = "creator.windows.workflow.install_macusboot.unmounting"
    static let windowsInstallMacUSBootCheckingLayout = "creator.windows.workflow.install_macusboot.checking_layout"
    static let windowsInstallMacUSBootWritingStageTwo = "creator.windows.workflow.install_macusboot.writing_stage_two"
    static let windowsInstallMacUSBootWritingMBR = "creator.windows.workflow.install_macusboot.writing_mbr"
    static let windowsInstallMacUSBootVerifying = "creator.windows.workflow.install_macusboot.verifying"
    static let windowsInstallMacUSBootRemounting = "creator.windows.workflow.install_macusboot.remounting"
    static let windowsCleanupTempTitle = "creator.windows.workflow.cleanup_temp.title"
    static let windowsCleanupTempStatus = "creator.windows.workflow.cleanup_temp.status"
    static let startingTitle = "creator.workflow.starting.title"
    static let startingStatus = "creator.workflow.starting.status"
    static let initializingStatus = "creator.workflow.initializing.status"

    static let catalinaCleanupTitle = "creator.macos.workflow.catalina_cleanup.title"
    static let catalinaCleanupStatus = "creator.macos.workflow.catalina_cleanup.status"
    static let catalinaCopyTitle = "creator.macos.workflow.catalina_copy.title"
    static let catalinaCopyStatus = "creator.macos.workflow.catalina_copy.status"
    static let catalinaXattrTitle = "creator.macos.workflow.catalina_xattr.title"
    static let catalinaXattrStatus = "creator.macos.workflow.catalina_xattr.status"

    static let cleanupTempTitle = "creator.workflow.cleanup_temp.title"
    static let cleanupTempStatus = "creator.workflow.cleanup_temp.status"

    static let finalizeTitle = "creator.workflow.finalize.title"
    static let finalizeStatus = "creator.workflow.finalize.status"

    // Normalize presentation identifiers from helper versions using the previous catalog.
    static func catalogKey(for key: String) -> String {
        guard key.hasPrefix("helper.workflow.") else { return key }
        let components = key.dropFirst("helper.workflow.".count).split(separator: ".", maxSplits: 1)
        guard components.count == 2, let prefix = legacyStageCatalogPrefixes[String(components[0])] else {
            return key
        }
        return prefix + "." + components[1]
    }

    private static let legacyStageCatalogPrefixes: [String: String] = [
        "catalina_cleanup": "creator.macos.workflow.catalina_cleanup",
        "catalina_copy": "creator.macos.workflow.catalina_copy",
        "catalina_xattr": "creator.macos.workflow.catalina_xattr",
        "cleanup_temp": "creator.workflow.cleanup_temp",
        "createinstallmedia": "creator.macos.workflow.createinstallmedia",
        "finalize": "creator.workflow.finalize",
        "imagescan": "creator.macos.workflow.imagescan",
        "initializing": "creator.workflow.initializing",
        "linux_raw_copy": "creator.linux.workflow.raw_copy",
        "linux_unmount_target": "creator.workflow.unmount_target",
        "linux_verify_write": "creator.linux.workflow.verify_write",
        "ppc_format": "creator.macos.workflow.ppc_format",
        "ppc_restore": "creator.macos.workflow.ppc_restore",
        "preformat": "creator.macos.workflow.preformat",
        "prepare_source": "creator.workflow.prepare_source",
        "restore": "creator.macos.workflow.restore",
        "starting": "creator.workflow.starting",
        "windows_cleanup_temp": "creator.windows.workflow.cleanup_temp",
        "windows_create_autounattend": "creator.windows.workflow.create_autounattend",
        "windows_create_media": "creator.windows.workflow.create_media",
        "windows_install_macusboot": "creator.windows.workflow.install_macusboot",
        "windows_prepare_source": "creator.windows.workflow.prepare_source",
        "windows_prepare_target": "creator.windows.workflow.prepare_target",
        "windows_split_wim": "creator.windows.workflow.split_wim",
        "windows_verify_media": "creator.windows.workflow.verify_media",
    ]

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
        case "windows_create_autounattend":
            return HelperWorkflowStageLocalization(titleKey: windowsCreateAutounattendTitle, statusKey: windowsCreateAutounattendStatus)
        case "windows_verify_media":
            return HelperWorkflowStageLocalization(titleKey: windowsVerifyMediaTitle, statusKey: windowsVerifyMediaStatus)
        case "windows_install_macusboot":
            return HelperWorkflowStageLocalization(
                titleKey: windowsInstallMacUSBootTitle,
                statusKey: windowsInstallMacUSBootCheckingArtifact
            )
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
        String(localized: "creator.workflow.prepare_source.title", table: "Creator"),
        String(localized: "creator.workflow.prepare_source.status", table: "Creator"),
        String(localized: "creator.macos.workflow.preformat.title", table: "Creator"),
        String(localized: "creator.macos.workflow.preformat.status", table: "Creator"),
        String(localized: "creator.macos.workflow.imagescan.title", table: "Creator"),
        String(localized: "creator.macos.workflow.imagescan.status", table: "Creator"),
        String(localized: "creator.macos.workflow.restore.title", table: "Creator"),
        String(localized: "creator.macos.workflow.restore.status", table: "Creator"),
        String(localized: "creator.macos.workflow.ppc_format.title", table: "Creator"),
        String(localized: "creator.macos.workflow.ppc_format.status", table: "Creator"),
        String(localized: "creator.macos.workflow.ppc_restore.title", table: "Creator"),
        String(localized: "creator.macos.workflow.ppc_restore.status", table: "Creator"),
        String(localized: "creator.macos.workflow.createinstallmedia.title", table: "Creator"),
        String(localized: "creator.macos.workflow.createinstallmedia.status", table: "Creator"),
        String(localized: "creator.workflow.unmount_target.title", table: "Creator"),
        String(localized: "creator.workflow.unmount_target.status", table: "Creator"),
        String(localized: "creator.linux.workflow.raw_copy.title", table: "Creator"),
        String(localized: "creator.linux.workflow.raw_copy.status", table: "Creator"),
        String(localized: "creator.linux.workflow.verify_write.title", table: "Creator"),
        String(localized: "creator.linux.workflow.verify_write.status", table: "Creator"),
        String(localized: "creator.windows.workflow.prepare_source.title", table: "Creator"),
        String(localized: "creator.windows.workflow.prepare_source.status", table: "Creator"),
        String(localized: "creator.windows.workflow.prepare_target.title", table: "Creator"),
        String(localized: "creator.windows.workflow.prepare_target.status", table: "Creator"),
        String(localized: "creator.windows.workflow.create_media.title", table: "Creator"),
        String(localized: "creator.windows.workflow.create_media.status", table: "Creator"),
        String(localized: "creator.windows.workflow.split_wim.title", table: "Creator"),
        String(localized: "creator.windows.workflow.split_wim.status", table: "Creator"),
        String(localized: "creator.windows.workflow.create_autounattend.title", table: "Creator"),
        String(localized: "creator.windows.workflow.create_autounattend.status", table: "Creator"),
        String(localized: "creator.windows.workflow.verify_media.title", table: "Creator"),
        String(localized: "creator.windows.workflow.verify_media.status", table: "Creator"),
        String(localized: "creator.windows.workflow.install_macusboot.title", table: "Creator"),
        String(localized: "creator.windows.workflow.install_macusboot.checking_artifact", table: "Creator"),
        String(localized: "creator.windows.workflow.install_macusboot.unmounting", table: "Creator"),
        String(localized: "creator.windows.workflow.install_macusboot.checking_layout", table: "Creator"),
        String(localized: "creator.windows.workflow.install_macusboot.writing_stage_two", table: "Creator"),
        String(localized: "creator.windows.workflow.install_macusboot.writing_mbr", table: "Creator"),
        String(localized: "creator.windows.workflow.install_macusboot.verifying", table: "Creator"),
        String(localized: "creator.windows.workflow.install_macusboot.remounting", table: "Creator"),
        String(localized: "creator.windows.workflow.cleanup_temp.title", table: "Creator"),
        String(localized: "creator.windows.workflow.cleanup_temp.status", table: "Creator"),
        String(localized: "creator.workflow.starting.title", table: "Creator"),
        String(localized: "creator.workflow.starting.status", table: "Creator"),
        String(localized: "creator.workflow.initializing.status", table: "Creator"),
        String(localized: "creator.macos.workflow.catalina_cleanup.title", table: "Creator"),
        String(localized: "creator.macos.workflow.catalina_cleanup.status", table: "Creator"),
        String(localized: "creator.macos.workflow.catalina_copy.title", table: "Creator"),
        String(localized: "creator.macos.workflow.catalina_copy.status", table: "Creator"),
        String(localized: "creator.macos.workflow.catalina_xattr.title", table: "Creator"),
        String(localized: "creator.macos.workflow.catalina_xattr.status", table: "Creator"),
        String(localized: "creator.workflow.cleanup_temp.title", table: "Creator"),
        String(localized: "creator.workflow.cleanup_temp.status", table: "Creator"),
        String(localized: "creator.workflow.finalize.title", table: "Creator"),
        String(localized: "creator.workflow.finalize.status", table: "Creator")
    ]
}
