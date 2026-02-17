import SwiftUI

enum VisualSystemMode {
    case liquidGlass
    case legacy
}

func currentVisualMode() -> VisualSystemMode {
    if #available(macOS 26.0, *) {
        return .liquidGlass
    }
    return .legacy
}

enum MacUSBSurfaceTone {
    case neutral
    case subtle
    case info
    case success
    case warning
    case error
    case active
}

private extension MacUSBSurfaceTone {
    var usesStableSurfaceOnLiquidGlass: Bool {
        switch self {
        case .neutral, .subtle:
            return true
        case .info, .success, .warning, .error, .active:
            return false
        }
    }

    func fallbackFillColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .neutral:
            return colorScheme == .dark
                ? Color.white.opacity(0.065)
                : Color.black.opacity(0.038)
        case .subtle:
            return colorScheme == .dark
                ? Color.white.opacity(0.060)
                : Color.black.opacity(0.032)
        case .info:
            return Color.blue.opacity(0.10)
        case .success:
            return Color.green.opacity(0.10)
        case .warning:
            return Color.orange.opacity(0.10)
        case .error:
            return Color.red.opacity(0.10)
        case .active:
            return Color.accentColor.opacity(0.12)
        }
    }

    func fallbackStrokeColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .neutral:
            return colorScheme == .dark
                ? Color.white.opacity(0.11)
                : Color.black.opacity(0.09)
        case .subtle:
            return colorScheme == .dark
                ? Color.white.opacity(0.10)
                : Color.black.opacity(0.08)
        case .info:
            return Color.blue.opacity(0.25)
        case .success:
            return Color.green.opacity(0.25)
        case .warning:
            return Color.orange.opacity(0.30)
        case .error:
            return Color.red.opacity(0.30)
        case .active:
            return Color.accentColor.opacity(0.30)
        }
    }

    @available(macOS 26.0, *)
    var glass: Glass {
        switch self {
        case .neutral, .subtle:
            return .regular.interactive(false)
        case .info:
            return .regular.tint(.blue.opacity(0.14)).interactive(false)
        case .success:
            return .regular.tint(.green.opacity(0.14)).interactive(false)
        case .warning:
            return .regular.tint(.orange.opacity(0.16)).interactive(false)
        case .error:
            return .regular.tint(.red.opacity(0.16)).interactive(false)
        case .active:
            return .regular.tint(.accentColor.opacity(0.18)).interactive(false)
        }
    }
}

private struct MacUSBTopRoundedRectangle: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width / 2, rect.height))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MacUSBPanelSurfaceModifier: ViewModifier {
    let tone: MacUSBSurfaceTone
    let cornerRadius: CGFloat?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let radius = cornerRadius ?? MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode())
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if #available(macOS 26.0, *), !tone.usesStableSurfaceOnLiquidGlass {
            content
                .glassEffect(tone.glass, in: shape)
        } else {
            content
                .background(
                    shape
                        .fill(tone.fallbackFillColor(for: colorScheme))
                )
                .overlay(
                    shape
                        .stroke(tone.fallbackStrokeColor(for: colorScheme), lineWidth: 0.5)
                )
        }
    }
}

private struct MacUSBDockedBarSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let mode = currentVisualMode()
        let shape = MacUSBTopRoundedRectangle(
            cornerRadius: MacUSBDesignTokens.dockedBarTopCornerRadius(for: mode)
        )

        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(false), in: shape)
        } else {
            content
                .background(shape.fill(MacUSBSurfaceTone.subtle.fallbackFillColor(for: colorScheme)))
                .overlay(
                    shape.stroke(MacUSBSurfaceTone.subtle.fallbackStrokeColor(for: colorScheme), lineWidth: 0.5)
                )
        }
    }
}

private struct MacUSBPrimaryButtonStyleModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .opacity(isEnabled ? 1.0 : 0.55)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.accentColor)
                .opacity(isEnabled ? 1.0 : 0.55)
        }
    }
}

private struct MacUSBSecondaryButtonStyleModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .controlSize(.large)
                .opacity(isEnabled ? 1.0 : 0.55)
        } else {
            content
                .buttonStyle(.bordered)
                .controlSize(.large)
                .opacity(isEnabled ? 1.0 : 0.55)
        }
    }
}

extension View {
    func macUSBPanelSurface(_ tone: MacUSBSurfaceTone = .neutral, cornerRadius: CGFloat? = nil) -> some View {
        modifier(MacUSBPanelSurfaceModifier(tone: tone, cornerRadius: cornerRadius))
    }

    func macUSBDockedBarSurface() -> some View {
        modifier(MacUSBDockedBarSurfaceModifier())
    }

    func macUSBPrimaryButtonStyle(isEnabled: Bool = true) -> some View {
        modifier(MacUSBPrimaryButtonStyleModifier(isEnabled: isEnabled))
    }

    func macUSBSecondaryButtonStyle(isEnabled: Bool = true) -> some View {
        modifier(MacUSBSecondaryButtonStyleModifier(isEnabled: isEnabled))
    }
}
