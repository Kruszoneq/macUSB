import SwiftUI

enum MacUSBDesignTokens {
    static let windowWidth: CGFloat = 550
    static let windowHeight: CGFloat = 750

    static let contentHorizontalPadding: CGFloat = 16
    static let contentVerticalPadding: CGFloat = 16
    static let contentSectionSpacing: CGFloat = 14

    static let panelInnerPadding: CGFloat = 14
    static let compactPanelInnerPadding: CGFloat = 10

    static let bottomBarHorizontalPadding: CGFloat = 16
    static let bottomBarVerticalPadding: CGFloat = 14
    static let bottomBarContentSpacing: CGFloat = 12

    static let iconColumnWidth: CGFloat = 32

    static func panelCornerRadius(for mode: VisualSystemMode) -> CGFloat {
        switch mode {
        case .liquidGlass:
            return 14
        case .legacy:
            return 10
        }
    }

    static func prominentPanelCornerRadius(for mode: VisualSystemMode) -> CGFloat {
        switch mode {
        case .liquidGlass:
            return 16
        case .legacy:
            return 12
        }
    }

    static func dockedBarTopCornerRadius(for mode: VisualSystemMode) -> CGFloat {
        switch mode {
        case .liquidGlass:
            return 14
        case .legacy:
            return 10
        }
    }
}
