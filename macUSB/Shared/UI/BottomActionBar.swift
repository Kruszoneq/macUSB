import SwiftUI

struct BottomActionBar<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: MacUSBDesignTokens.bottomBarContentSpacing) {
            content
        }
        .padding(.horizontal, MacUSBDesignTokens.bottomBarHorizontalPadding)
        .padding(.vertical, MacUSBDesignTokens.bottomBarVerticalPadding)
        .frame(maxWidth: .infinity)
        .macUSBDockedBarSurface()
    }
}
