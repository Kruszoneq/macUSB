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

    static let catalinaFinalizeTitle = "helper.workflow.catalina_finalize.title"
    static let catalinaCleanupStatus = "helper.workflow.catalina_cleanup.status"
    static let catalinaCopyStatus = "helper.workflow.catalina_copy.status"
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
        case "catalina_cleanup":
            return HelperWorkflowStageLocalization(titleKey: catalinaFinalizeTitle, statusKey: catalinaCleanupStatus)
        case "catalina_copy":
            return HelperWorkflowStageLocalization(titleKey: catalinaFinalizeTitle, statusKey: catalinaCopyStatus)
        case "catalina_xattr":
            return HelperWorkflowStageLocalization(titleKey: catalinaFinalizeTitle, statusKey: catalinaXattrStatus)
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
        String(localized: "helper.workflow.catalina_finalize.title"),
        String(localized: "helper.workflow.catalina_cleanup.status"),
        String(localized: "helper.workflow.catalina_copy.status"),
        String(localized: "helper.workflow.catalina_xattr.status"),
        String(localized: "helper.workflow.cleanup_temp.title"),
        String(localized: "helper.workflow.cleanup_temp.status"),
        String(localized: "helper.workflow.finalize.title"),
        String(localized: "helper.workflow.finalize.status")
    ]
}
