import SwiftUI
import Combine

@MainActor
final class AppToastCenter: ObservableObject {
    static let shared = AppToastCenter()

    @Published private(set) var toast: AppToast?

    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func showHelperAutoUpdateRunning() {
        dismissWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.28)) {
            toast = AppToast(
                state: .running,
                titleKey: "app.toast.helper_auto_update.running.title",
                messageKey: "app.toast.helper_auto_update.running.message"
            )
        }
    }

    func showHelperAutoUpdateCompleted(visibleFor duration: TimeInterval = 5) {
        dismissWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.28)) {
            toast = AppToast(
                state: .completed,
                titleKey: "app.toast.helper_auto_update.completed.title",
                messageKey: "app.toast.helper_auto_update.completed.message"
            )
        }
        scheduleDismiss(after: duration)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        withAnimation(.easeInOut(duration: 0.26)) {
            toast = nil
        }
    }

    private func scheduleDismiss(after duration: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismiss()
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}

struct AppToast: Equatable {
    enum State: Equatable {
        case running
        case completed
    }

    let state: State
    let titleKey: String
    let messageKey: String
}

struct AppToastOverlay: View {
    let toast: AppToast?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let toast {
                AppToastView(toast: toast)
                    .padding(.horizontal, MacUSBDesignTokens.contentHorizontalPadding)
                    .padding(.bottom, MacUSBDesignTokens.dockedBarMinHeight + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.28), value: toast)
    }
}

private struct AppToastView: View {
    let toast: AppToast

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(toast.titleKey))
                    .font(.headline)
                    .lineLimit(1)

                Text(LocalizedStringKey(toast.messageKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 470, alignment: .leading)
        .appToastSurface()
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toast.state {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct AppToastSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let radius = MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode())
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(false), in: shape)
        } else {
            content
                .background(
                    shape.fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.075)
                            : Color.black.opacity(0.040)
                    )
                )
                .overlay(
                    shape.stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.10),
                        lineWidth: 0.5
                    )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 18, y: 8)
        }
    }
}

private extension View {
    func appToastSurface() -> some View {
        modifier(AppToastSurfaceModifier())
    }
}
