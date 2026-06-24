import SwiftUI

struct AnalysisChecksumSheetView: View {
    @StateObject private var viewModel: AnalysisChecksumViewModel
    @State private var didCopyChecksum = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(sourceURL: URL) {
        _viewModel = StateObject(wrappedValue: AnalysisChecksumViewModel(fileURL: sourceURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }

            Spacer(minLength: 0)
            footer
        }
        .font(.subheadline)
        .padding(18)
        .frame(width: 420, alignment: .top)
        .frame(minHeight: 240, alignment: .top)
        .interactiveDismissDisabled(viewModel.isRunning)
        .task {
            viewModel.start()
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            viewModel.cancelIfRunningForSheetClose()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.title3)
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(.primary)
                Text(String(localized: "checksum.sheet.title"))
                    .font(.headline)
                Spacer()
            }

            Divider()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .ready:
            Text(String(localized: "checksum.sheet.ready.description"))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .running:
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "checksum.sheet.running.description"))
                    .foregroundColor(.secondary)
                ProgressView(value: viewModel.progress)
                Text(
                    String(
                        format: String(localized: "checksum.sheet.progress.percent"),
                        Int((viewModel.progress * 100).rounded())
                    )
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        case .completed:
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "checksum.sheet.completed.description"))
                    .foregroundColor(.secondary)
                if let checksum = viewModel.checksum {
                    Text(checksum)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .macUSBPanelSurface(.subtle)
                }
            }
        case .cancelled:
            Text(String(localized: "checksum.sheet.cancelled.description"))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            Text(viewModel.failureMessage ?? String(localized: "checksum.sheet.failed.description"))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            if viewModel.phase == .completed, viewModel.checksum != nil {
                Button {
                    copyChecksum()
                } label: {
                    copyButtonIcon
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .help(String(localized: "checksum.sheet.copy.button.help"))
                .macUSBSecondaryButtonStyle()
            }

            if viewModel.phase != .ready {
                Button {
                    handlePrimaryButton()
                } label: {
                    Text(primaryButtonTitle)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .macUSBPrimaryButtonStyle()
            }
        }
    }

    private var copyButtonIcon: some View {
        ZStack {
            Image(systemName: "doc.on.doc")
                .opacity(didCopyChecksum ? 0 : 1)
                .scaleEffect(didCopyChecksum ? 0.8 : 1)
            Image(systemName: "checkmark")
                .opacity(didCopyChecksum ? 1 : 0)
                .scaleEffect(didCopyChecksum ? 1 : 0.8)
        }
        .frame(width: 18, height: 18)
        .animation(.easeInOut(duration: 0.18), value: didCopyChecksum)
    }

    private var primaryButtonTitle: String {
        switch viewModel.phase {
        case .running:
            return String(localized: "Anuluj")
        case .ready, .completed, .cancelled, .failed:
            return String(localized: "Zamknij")
        }
    }

    private func handlePrimaryButton() {
        switch viewModel.phase {
        case .running:
            viewModel.cancelFromUser()
        case .ready, .completed, .cancelled, .failed:
            dismiss()
        }
    }

    private func copyChecksum() {
        viewModel.copyChecksumToPasteboard()
        copyFeedbackTask?.cancel()

        withAnimation(.easeInOut(duration: 0.18)) {
            didCopyChecksum = true
        }

        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    didCopyChecksum = false
                }
                copyFeedbackTask = nil
            }
        }
    }
}
