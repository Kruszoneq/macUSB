import SwiftUI

struct AnalysisChecksumSheetView: View {
    @StateObject private var viewModel: AnalysisChecksumViewModel
    @Environment(\.dismiss) private var dismiss

    init(sourceURL: URL) {
        _viewModel = StateObject(wrappedValue: AnalysisChecksumViewModel(fileURL: sourceURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            footer
        }
        .font(.subheadline)
        .padding(18)
        .frame(width: 420)
        .interactiveDismissDisabled(viewModel.isRunning)
        .onDisappear {
            viewModel.cancelIfRunningForSheetClose()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.title3)
                    .foregroundColor(.accentColor)
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
                    viewModel.copyChecksumToPasteboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .help(String(localized: "checksum.sheet.copy.button.help"))
                .macUSBSecondaryButtonStyle()
            }

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

    private var primaryButtonTitle: String {
        switch viewModel.phase {
        case .ready:
            return String(localized: "checksum.sheet.check.button")
        case .running:
            return String(localized: "Anuluj")
        case .completed, .cancelled, .failed:
            return String(localized: "Zamknij")
        }
    }

    private func handlePrimaryButton() {
        switch viewModel.phase {
        case .ready:
            viewModel.start()
        case .running:
            viewModel.cancelFromUser()
        case .completed, .cancelled, .failed:
            dismiss()
        }
    }
}
