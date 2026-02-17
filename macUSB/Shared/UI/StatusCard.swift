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
