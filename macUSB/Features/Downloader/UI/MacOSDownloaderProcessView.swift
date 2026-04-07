import SwiftUI

extension MacOSDownloaderWindowShellView {
    func downloaderProgressSection(for entry: MacOSInstallerEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pobieranie systemu")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
                    StatusCard(tone: .subtle, density: .compact) {
                        HStack(spacing: 12) {
                            installerIconView(for: entry)
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.name) \(entry.version)")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                if shouldShowBuild(entry.build) {
                                    Text(entry.build)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }

                    if downloadFlowModel.isFinished {
                        downloadSummaryView
                    } else {
                        if let networkWarningMessage = downloadFlowModel.networkWarningMessage,
                           !networkWarningMessage.isEmpty {
                            StatusCard(tone: .warning, density: .compact) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.orange)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Połączenie internetowe zostało utracone")
                                            .font(.subheadline.weight(.semibold))
                                        Text(networkWarningMessage)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }

                        if !downloadFlowModel.suppressInlineFailureMessage,
                           let failureMessage = downloadFlowModel.failureMessage,
                           !failureMessage.isEmpty {
                            StatusCard(tone: .warning, density: .compact) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nie udało się dokończyć pobierania")
                                        .font(.subheadline.weight(.semibold))
                                    Text(failureMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        downloadStageSectionDivider

                        VStack(spacing: 10) {
                            ForEach(MontereyDownloadFlowStage.allCases, id: \.self) { stage in
                                downloadStageRow(for: stage)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(MacUSBDesignTokens.panelInnerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .macUSBPanelSurface(.neutral)
            .clipped()
#if swift(>=5.9)
            .scrollIndicators(.hidden)
#endif
        }
    }

    var downloadStageSectionDivider: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
            Text("Etapy pobierania")
                .font(.caption)
                .foregroundStyle(.secondary)
            Capsule()
                .fill(Color.secondary.opacity(0.20))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    func downloadStageRow(for stage: MontereyDownloadFlowStage) -> some View {
        let stageState = downloadFlowModel.visualState(for: stage)

        switch stageState {
        case .pending:
            StatusCard(tone: .subtle, density: .compact) {
                HStack(spacing: 12) {
                    Image(systemName: pendingIconForDownloadStage(stage))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text(downloadStageTitle(for: stage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

        case .active:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: activeIconForDownloadStage(stage))
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    Text(downloadStageTitle(for: stage))
                        .font(.headline)
                    Spacer()
                    if stage == .downloading {
                        Text(downloadProgressText())
                            .font(.title3.monospacedDigit())
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }
                }

                if let description = downloadStageDescription(for: stage) {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let progress = downloadStageProgress(for: stage) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                if stage == .downloading {
                    HStack {
                        Text(verbatim: downloadSpeedLabelText())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(downloadFlowModel.downloadTransferredText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if !downloadFlowModel.discoveredDownloadItems.isEmpty {
                        downloadManifestInlineListView
                    }
                }
            }
            .padding(MacUSBDesignTokens.panelInnerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(activeStageBackgroundFill)
            .overlay(activeStageBackgroundStroke)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MacUSBDesignTokens.prominentPanelCornerRadius(for: currentVisualMode()),
                    style: .continuous
                )
            )

        case .completed:
            StatusCard(tone: .neutral, density: .compact) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                        .frame(width: 24)
                    Text(downloadStageTitle(for: stage))
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
    }

    func pendingIconForDownloadStage(_ stage: MontereyDownloadFlowStage) -> String {
        switch stage {
        case .connection:
            return "network"
        case .downloading:
            return "arrow.down.circle"
        case .verifying:
            return "checkmark.shield"
        case .buildingInstaller:
            return "shippingbox"
        case .cleanup:
            return "checkmark.circle"
        }
    }

    func activeIconForDownloadStage(_ stage: MontereyDownloadFlowStage) -> String {
        switch stage {
        case .connection:
            return "network"
        case .downloading:
            return "arrow.down.circle.fill"
        case .verifying:
            return "checkmark.shield.fill"
        case .buildingInstaller:
            return "shippingbox.fill"
        case .cleanup:
            return "checkmark.circle.fill"
        }
    }

    func downloadStageTitle(for stage: MontereyDownloadFlowStage) -> String {
        switch stage {
        case .connection:
            return "Łączenie z serwerami Apple"
        case .downloading:
            return "Pobieranie plików"
        case .verifying:
            return "Weryfikowanie plików"
        case .buildingInstaller:
            return "Przygotowywanie instalatora \(installerFamilyLabelForBuildStage())"
        case .cleanup:
            return "Kończenie pracy"
        }
    }

    private func installerFamilyLabelForBuildStage() -> String {
        guard let entry = activeDownloadEntry else {
            return "macOS"
        }
        let parts = entry.version.split(separator: ".")
        guard let major = parts.first.flatMap({ Int($0) }) else {
            return "macOS"
        }
        let minor = parts.dropFirst().first.flatMap { Int($0) } ?? -1

        if major == 10, minor == 7 {
            return "Mac OS X"
        }
        if major == 10, (8...11).contains(minor) {
            return "OS X"
        }
        return "macOS"
    }

    func downloadStageDescription(for stage: MontereyDownloadFlowStage) -> String? {
        switch stage {
        case .connection:
            return downloadFlowModel.connectionStatusText
        case .downloading:
            return downloadFlowModel.downloadFileName
        case .verifying:
            let fileName = downloadFlowModel.verifyFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileName.isEmpty else { return nil }
            if fileName == "Oczekiwanie..." {
                return fileName
            }
            return "Weryfikowanie pliku \(fileName)..."
        case .buildingInstaller:
            return downloadFlowModel.buildStatusText
        case .cleanup:
            return downloadFlowModel.cleanupStatusText
        }
    }

    func downloadStageProgress(for stage: MontereyDownloadFlowStage) -> Double? {
        switch stage {
        case .connection:
            return nil
        case .downloading:
            return downloadFlowModel.downloadProgress
        case .verifying:
            return downloadFlowModel.verifyProgress
        case .buildingInstaller:
            return downloadFlowModel.buildProgress
        case .cleanup:
            return downloadFlowModel.cleanupProgress
        }
    }

    func downloadProgressText() -> String {
        let bounded = min(max(downloadFlowModel.downloadProgress, 0), 1)
        return "\(Int((bounded * 100).rounded()))%"
    }

    func downloadSpeedLabelText() -> String {
        let speed = downloadFlowModel.downloadSpeedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if speed.isEmpty {
            return String(localized: "Szybkość pobierania: - MB/s")
        }
        return String(
            format: String(localized: "Szybkość pobierania: %@"),
            speed
        )
    }

    var downloadManifestInlineListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pliki do pobrania")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(downloadFlowModel.discoveredDownloadItems) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: iconForManifestItemStatus(item))
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .frame(width: 12)
                    Text(item.name)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(item.expectedSizeText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macUSBPanelSurface(.subtle)
    }

    private func iconForManifestItemStatus(_ item: DownloadManifestItem) -> String {
        if downloadFlowModel.completedStages.contains(.downloading) {
            return "checkmark.circle.fill"
        }

        let currentIndex = downloadFlowModel.downloadCurrentIndex
        let itemIndex = item.order + 1
        if downloadFlowModel.currentStage == .downloading {
            if itemIndex < currentIndex {
                return "checkmark.circle.fill"
            }
            if itemIndex == currentIndex {
                return "arrow.down.circle.fill"
            }
        }

        return "clock.fill"
    }

    private var activeStageBackgroundFill: some View {
        RoundedRectangle(
            cornerRadius: MacUSBDesignTokens.prominentPanelCornerRadius(for: currentVisualMode()),
            style: .continuous
        )
        .fill(Color.accentColor.opacity(0.14))
    }

    private var activeStageBackgroundStroke: some View {
        RoundedRectangle(
            cornerRadius: MacUSBDesignTokens.prominentPanelCornerRadius(for: currentVisualMode()),
            style: .continuous
        )
        .stroke(Color.accentColor.opacity(0.30), lineWidth: 0.6)
    }
}
