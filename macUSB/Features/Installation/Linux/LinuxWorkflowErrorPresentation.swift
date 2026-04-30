import Foundation

struct LinuxWorkflowErrorPresentation {
    let iconSystemName: String
    let titleKey: String
    let descriptionKey: String
}

enum LinuxWorkflowErrorMapper {
    private static let titleKey = "installation.error.card.warning.title"
    private static let genericKey = "installation.error.workflow.generic"

    static func presentation(for result: HelperWorkflowResultPayload) -> LinuxWorkflowErrorPresentation? {
        guard !result.isUserCancelled else { return nil }

        if result.failedStage == "linux_verify_write" {
            if result.errorCode == 3 {
                return LinuxWorkflowErrorPresentation(
                    iconSystemName: "exclamationmark.triangle.fill",
                    titleKey: titleKey,
                    descriptionKey: "installation.error.linux.verify_write.mismatch"
                )
            }
            if result.errorCode == 2 {
                return LinuxWorkflowErrorPresentation(
                    iconSystemName: "exclamationmark.triangle.fill",
                    titleKey: titleKey,
                    descriptionKey: "installation.error.linux.verify_write.short_read"
                )
            }
            return LinuxWorkflowErrorPresentation(
                iconSystemName: "exclamationmark.triangle.fill",
                titleKey: titleKey,
                descriptionKey: "installation.error.linux.verify_write.generic"
            )
        }

        return LinuxWorkflowErrorPresentation(
            iconSystemName: "exclamationmark.triangle.fill",
            titleKey: titleKey,
            descriptionKey: genericKey
        )
    }
}

enum LinuxWorkflowErrorLocalizationExtractionAnchors {
    // Keep literal keys here so String Catalog extraction can detect dynamic keys used at runtime.
    static let anchoredValues: [String] = [
        String(localized: "installation.error.card.warning.title"),
        String(localized: "installation.error.linux.verify_write.mismatch"),
        String(localized: "installation.error.linux.verify_write.short_read"),
        String(localized: "installation.error.linux.verify_write.generic"),
        String(localized: "installation.error.workflow.generic")
    ]
}
