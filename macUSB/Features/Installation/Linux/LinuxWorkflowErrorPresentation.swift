import Foundation

struct LinuxWorkflowErrorPresentation {
    let iconSystemName: String
    let titleKey: String
    let descriptionKey: String
}

enum LinuxWorkflowErrorMapper {
    private static let titleKey = "finish.error.card.warning.title"
    private static let genericKey = "finish.error.workflow.generic"

    static func presentation(for result: HelperWorkflowResultPayload) -> LinuxWorkflowErrorPresentation? {
        guard !result.isUserCancelled else { return nil }

        if result.failedStage == "linux_verify_write" {
            if result.errorCode == 3 {
                return LinuxWorkflowErrorPresentation(
                    iconSystemName: "exclamationmark.triangle.fill",
                    titleKey: titleKey,
                    descriptionKey: "finish.error.verify_write.mismatch"
                )
            }
            if result.errorCode == 2 {
                return LinuxWorkflowErrorPresentation(
                    iconSystemName: "exclamationmark.triangle.fill",
                    titleKey: titleKey,
                    descriptionKey: "finish.error.verify_write.short_read"
                )
            }
            return LinuxWorkflowErrorPresentation(
                iconSystemName: "exclamationmark.triangle.fill",
                titleKey: titleKey,
                descriptionKey: "finish.linux.error.verify_write.generic"
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
        String(localized: "finish.error.card.warning.title", table: "FinishUSB"),
        String(localized: "finish.error.verify_write.mismatch", table: "FinishUSB"),
        String(localized: "finish.error.verify_write.short_read", table: "FinishUSB"),
        String(localized: "finish.linux.error.verify_write.generic", table: "FinishUSB"),
        String(localized: "finish.error.workflow.generic", table: "FinishUSB"),
        String(localized: "finish.raw_image.error.verify_write.generic", table: "FinishUSB")
    ]
}
