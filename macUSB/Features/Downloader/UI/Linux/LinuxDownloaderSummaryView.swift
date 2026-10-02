import SwiftUI
import AppKit

extension MacOSDownloaderWindowShellView {
    var linuxDownloadSummaryView: some View {
        let isFailure = linuxDownloadFlowModel.workflowState == .failed
        let finalImageURL = linuxDownloadFlowModel.finalImageURL
        let tint: Color = isFailure ? .red : .green

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isFailure ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(tint)
                Text(isFailure
                     ? String(localized: "Nie udało się dokończyć pobierania")
                     : String(localized: "Gotowe"))
                    .font(.headline)
            }

            downloadSummaryMetricRow(
                title: String(localized: "Pobrano danych"),
                value: linuxDownloadFlowModel.summaryTotalDownloadedText
            )
            downloadSummaryMetricRow(
                title: String(localized: "Średnia szybkość"),
                value: linuxDownloadFlowModel.summaryAverageSpeedText
            )
            downloadSummaryMetricRow(
                title: String(localized: "Czas pobierania"),
                value: linuxDownloadFlowModel.summaryDurationText
            )

            if let finalImageURL {
                Divider()
                downloadSummaryMetricRow(
                    title: String(localized: "downloader.linux.summary.image"),
                    value: finalImageURL.lastPathComponent
                )
                downloadSummaryMetricRow(
                    title: String(localized: "Lokalizacja"),
                    value: (finalImageURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                )
                downloadSummaryMetricRow(
                    title: String(localized: "downloader.linux.summary.checksum"),
                    value: String(localized: "downloader.linux.summary.checksum_verified")
                )
            }

            if isFailure,
               let failureMessage = linuxDownloadFlowModel.failureMessage,
               !failureMessage.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Szczegóły"))
                        .font(.subheadline.weight(.semibold))
                    Text(failureMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if finalImageURL != nil {
                VStack(spacing: 8) {
                    Button {
                        useDownloadedLinuxImageInAnalysis()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text(String(localized: "downloader.linux.summary.use_in_analysis"))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .macUSBSecondaryButtonStyle()

                    Button {
                        revealDownloadedLinuxImage()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                            Text(String(localized: "Pokaż w Finderze"))
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
            } else {
                Button {
                    returnToLinuxImageList()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.backward.circle.fill")
                        Text(String(localized: "downloader.linux.summary.back_to_list"))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
                .macUSBSecondaryButtonStyle()
                .padding(.top, 6)
            }
        }
        .padding(MacUSBDesignTokens.panelInnerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode()),
                style: .continuous
            )
            .fill(tint.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode()),
                style: .continuous
            )
            .stroke(tint.opacity(0.33), lineWidth: 0.6)
        )
    }

    func revealDownloadedLinuxImage() {
        if let finalImageURL = linuxDownloadFlowModel.finalImageURL,
           FileManager.default.fileExists(atPath: finalImageURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([finalImageURL])
            return
        }
        NSWorkspace.shared.open(linuxDestinationDirectoryURL)
    }

    func useDownloadedLinuxImageInAnalysis() {
        guard let finalImageURL = linuxDownloadFlowModel.finalImageURL,
              FileManager.default.fileExists(atPath: finalImageURL.path)
        else { return }

        AppLogging.info(
            "Passed downloaded image \(finalImageURL.path) to analysis.",
            stage: .downloader, workflow: .linux
        )
        AnalysisSelectionHandoff.shared.setPendingInstallerURL(finalImageURL)
        NotificationCenter.default.post(name: .macUSBNavigateToAnalysis, object: nil)
        NotificationCenter.default.post(name: .macUSBApplyPendingDownloaderInstaller, object: nil)
        handleCloseRequest()
    }
}
