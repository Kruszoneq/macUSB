import SwiftUI

struct AnalysisChecksumTriggerView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.subheadline)
                Text(String(localized: "analysis.checksum.analysis.trigger", table: "Analysis"))
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.accentColor)
            .contentShape(Rectangle())
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
        .help(String(localized: "analysis.checksum.analysis.trigger.help", table: "Analysis"))
    }
}
