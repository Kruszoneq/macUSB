import SwiftUI
import AppKit

extension MacOSDownloaderWindowShellView {
    var downloadSummaryView: some View {
        let isFailure = downloadFlowModel.workflowState == .failed
        let isPartial = isFailure && downloadFlowModel.isPartialSuccess
        let finalOutputURL = downloadFlowModel.finalDiskImageURL
            ?? downloadFlowModel.finalInstallerAppURL
        let hasFinalOutput = finalOutputURL != nil
        let shouldShowInstallerOutputSection = !isFailure || hasFinalOutput
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isPartial ? "exclamationmark.triangle.fill" : (isFailure ? "xmark.circle.fill" : "checkmark.circle.fill"))
                    .font(.title3)
                    .foregroundColor(isPartial ? .orange : (isFailure ? .red : .green))
                Text(isPartial
                     ? String(localized: "downloader.summary.partial.title", table: "Downloader")
                     : (isFailure
                        ? String(localized: "downloader.summary.failed.title", table: "Downloader")
                        : String(localized: "downloader.summary.success.title", table: "Downloader")))
                    .font(.headline)
            }

            if downloadFlowModel.hasExpiredButTrustedAppleSignature {
                expiredAppleSignatureInfoCard
            }

            downloadSummaryMetricRow(
                title: String(localized: "downloader.summary.transferred.label", table: "Downloader"),
                value: downloadFlowModel.summaryTotalDownloadedText
            )
            downloadSummaryMetricRow(
                title: String(localized: "downloader.summary.average_speed.label", table: "Downloader"),
                value: downloadFlowModel.summaryAverageSpeedText
            )
            downloadSummaryMetricRow(
                title: String(localized: "downloader.summary.duration.label", table: "Downloader"),
                value: downloadFlowModel.summaryDurationText
            )

            Divider()

            if shouldShowInstallerOutputSection {
                downloadSummaryMetricRow(
                    title: downloadFlowModel.finalDiskImageURL == nil
                        ? String(localized: "downloader.summary.installer.label", table: "Downloader")
                        : String(localized: "downloader.disk_image.summary.label", table: "Downloader"),
                    value: downloadFlowModel.summaryCreatedFileText
                )
                downloadSummaryMetricRow(
                    title: String(localized: "downloader.summary.location.label", table: "Downloader"),
                    value: downloadFlowModel.summaryLocationText
                )
            }
            downloadSummaryMetricRow(
                title: String(localized: "downloader.summary.cleanup.label", table: "Downloader"),
                value: downloadFlowModel.summaryTemporaryFilesText
            )

            if isFailure,
               !downloadFlowModel.suppressInlineFailureMessage,
               let failureMessage = downloadFlowModel.failureMessage,
               !failureMessage.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(isPartial ? String(localized: "downloader.summary.status.label", table: "Downloader") : String(localized: "downloader.summary.details.label", table: "Downloader"))
                        .font(.subheadline.weight(.semibold))
                    Text(failureMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if downloadFlowModel.diskImageSourceRemovalWarning,
               let retainedInstallerURL = downloadFlowModel.retainedSourceInstallerURL {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "downloader.summary.status.label", table: "Downloader"))
                        .font(.subheadline.weight(.semibold))
                    Text(
                        String(
                            format: String(
                                localized: "downloader.disk_image.partial.source_removal", table: "Downloader"
                            ),
                            retainedInstallerURL.path
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if shouldShowInstallerOutputSection {
                VStack(spacing: 8) {
                    if hasFinalOutput {
                        Button {
                            useDownloadedInstallerInAnalysis()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                Text(String(localized: "downloader.summary.analyze.help", table: "Downloader"))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .macUSBSecondaryButtonStyle()
                        .help(String(localized: "downloader.summary.analyze.help", table: "Downloader"))
                    }
                    
                    Button {
                        openPlannedInstallerFolder()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                            Text(String(localized: "downloader.summary.reveal.action", table: "Downloader"))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .macUSBSecondaryButtonStyle()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
        }
        .padding(MacUSBDesignTokens.panelInnerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(downloadSummaryBackgroundFill(isPartial: isPartial, isFailure: isFailure))
        .overlay(downloadSummaryBackgroundStroke(isPartial: isPartial, isFailure: isFailure))
        .clipShape(
            RoundedRectangle(
                cornerRadius: MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode()),
                style: .continuous
            )
        )
    }

    private func downloadSummaryBackgroundFill(isPartial: Bool, isFailure: Bool) -> some View {
        RoundedRectangle(
            cornerRadius: MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode()),
            style: .continuous
        )
        .fill(summaryFillColor(isPartial: isPartial, isFailure: isFailure))
    }

    private func downloadSummaryBackgroundStroke(isPartial: Bool, isFailure: Bool) -> some View {
        RoundedRectangle(
            cornerRadius: MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode()),
            style: .continuous
        )
        .stroke(summaryStrokeColor(isPartial: isPartial, isFailure: isFailure), lineWidth: 0.6)
    }

    private func summaryFillColor(isPartial: Bool, isFailure: Bool) -> Color {
        if isPartial {
            return Color.orange.opacity(0.16)
        }
        if isFailure {
            return Color.red.opacity(0.15)
        }
        return Color.green.opacity(0.15)
    }

    private func summaryStrokeColor(isPartial: Bool, isFailure: Bool) -> Color {
        if isPartial {
            return Color.orange.opacity(0.34)
        }
        if isFailure {
            return Color.red.opacity(0.34)
        }
        return Color.green.opacity(0.32)
    }

    func downloadSummaryMetricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var expiredAppleSignatureInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "downloader.signature.trusted.title", table: "Downloader"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(expiredAppleSignatureInfoDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: MacUSBDesignTokens.prominentPanelCornerRadius(for: currentVisualMode()),
                style: .continuous
            )
            .fill(Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: MacUSBDesignTokens.prominentPanelCornerRadius(for: currentVisualMode()),
                style: .continuous
            )
            .stroke(Color.secondary.opacity(0.24), lineWidth: 0.6)
        )
    }

    private var expiredAppleSignatureInfoDescription: String {
        String(localized: "downloader.signature.trusted.message", table: "Downloader")
    }

    func openPlannedInstallerFolder() {
        let finalOutputURL = downloadFlowModel.finalDiskImageURL
            ?? downloadFlowModel.finalInstallerAppURL
        if let finalOutputURL,
           FileManager.default.fileExists(atPath: finalOutputURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([finalOutputURL])
            return
        }

        let folderURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSWorkspace.shared.open(folderURL)
    }

    func useDownloadedInstallerInAnalysis() {
        guard let finalOutputURL = downloadFlowModel.finalDiskImageURL
                ?? downloadFlowModel.finalInstallerAppURL,
              FileManager.default.fileExists(atPath: finalOutputURL.path)
        else {
            return
        }

        AnalysisSelectionHandoff.shared.setPendingInstallerURL(finalOutputURL)
        NotificationCenter.default.post(name: .macUSBNavigateToAnalysis, object: nil)
        NotificationCenter.default.post(name: .macUSBApplyPendingDownloaderInstaller, object: nil)
        handleCloseRequest()
    }
}
