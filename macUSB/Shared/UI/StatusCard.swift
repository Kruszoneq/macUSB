import SwiftUI

struct StatusCard<Content: View>: View {
    let tone: MacUSBSurfaceTone
    let cornerRadius: CGFloat?
    private let content: Content

    init(
        tone: MacUSBSurfaceTone = .neutral,
        cornerRadius: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(MacUSBDesignTokens.panelInnerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macUSBPanelSurface(tone, cornerRadius: cornerRadius)
    }
}
