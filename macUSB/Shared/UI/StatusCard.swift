import SwiftUI

enum StatusCardDensity {
    case regular
    case compact
}

struct StatusCard<Content: View>: View {
    let tone: MacUSBSurfaceTone
    let cornerRadius: CGFloat?
    let density: StatusCardDensity
    private let content: Content

    init(
        tone: MacUSBSurfaceTone = .neutral,
        cornerRadius: CGFloat? = nil,
        density: StatusCardDensity = .regular,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        self.density = density
        self.content = content()
    }

    private var paddingValue: CGFloat {
        switch density {
        case .regular:
            return MacUSBDesignTokens.panelInnerPadding
        case .compact:
            return MacUSBDesignTokens.statusCardCompactPadding
        }
    }

    var body: some View {
        content
            .padding(paddingValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macUSBPanelSurface(tone, cornerRadius: cornerRadius)
    }
}

struct MacOSBetaBadge: View {
    let tint: Color

    var body: some View {
        Text(verbatim: "BETA")
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.46), lineWidth: 0.7)
            )
    }
}
