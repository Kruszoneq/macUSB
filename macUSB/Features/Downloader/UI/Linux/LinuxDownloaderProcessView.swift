import SwiftUI

extension MacOSDownloaderWindowShellView {
    func linuxProgressSection(for entry: LinuxImageEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Pobieranie systemu"))
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
                    StatusCard(tone: .subtle, density: .compact) {
                        HStack(spacing: 12) {
                            linuxDistributionIconView(for: entry.distribution)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(linuxEntrySecondaryText(for: entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if linuxDownloadFlowModel.isFinished {
                            linuxDownloadSummaryView
                                .transition(downloaderScreenTransition)
                        } else {
                            VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
                                downloadStageSectionDivider

                                VStack(spacing: 10) {
                                    ForEach(LinuxDownloadFlowStage.allCases, id: \.self) { stage in
                                        linuxDownloadStageRow(for: stage)
                                    }
                                }
                                .animation(
                                    MacUSBDesignTokens.stageTransitionAnimation,
                                    value: LinuxDownloadFlowStage.allCases.map(linuxDownloadFlowModel.visualState(for:))
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(downloaderScreenTransition)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .animation(
                        MacUSBDesignTokens.stageTransitionAnimation,
                        value: linuxDownloadFlowModel.isFinished
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(MacUSBDesignTokens.panelInnerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .macUSBPanelSurface(.neutral)
            .clipped()
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func linuxDownloadStageRow(for stage: LinuxDownloadFlowStage) -> some View {
        let stageState = linuxDownloadFlowModel.visualState(for: stage)

        Group {
            switch stageState {
            case .pending:
                StatusCard(tone: .subtle, density: .compact) {
                    HStack(spacing: 12) {
                        Image(systemName: linuxStageIcon(for: stage, isActive: false))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(linuxStageTitle(for: stage))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

            case .active:
                StatusCard(
                    tone: .active,
                    cornerRadius: MacUSBDesignTokens.prominentPanelCornerRadius(for: currentVisualMode())
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: linuxStageIcon(for: stage, isActive: true))
                                .font(.title3)
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text(linuxStageTitle(for: stage))
                                .font(.headline)
                            Spacer()
                            if let progress = linuxStageProgress(for: stage) {
                                Text(verbatim: "\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                                    .font(.title3.monospacedDigit())
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                        }

                        if let description = linuxStageDescription(for: stage) {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let progress = linuxStageProgress(for: stage) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                        }

                        if stage == .downloading {
                            HStack {
                                Text(
                                    String(
                                        format: String(localized: "Szybkość pobierania: %@"),
                                        linuxDownloadFlowModel.downloadSpeedText
                                    )
                                )
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                Spacer()
                                Text(linuxDownloadFlowModel.downloadTransferredText)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

            case .completed:
                StatusCard(tone: .neutral, density: .compact) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                            .frame(width: 24)
                        Text(linuxStageTitle(for: stage))
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
        }
        .id(stageState)
        .scaleEffect(MacUSBDesignTokens.stageScale(isActive: stageState == .active))
        .transition(MacUSBDesignTokens.stageCardTransition(isActive: stageState == .active))
    }

    private func linuxStageIcon(for stage: LinuxDownloadFlowStage, isActive: Bool) -> String {
        switch stage {
        case .connection:
            return "network"
        case .downloading:
            return isActive ? "arrow.down.circle.fill" : "arrow.down.circle"
        case .verifying:
            return isActive ? "checkmark.shield.fill" : "checkmark.shield"
        case .finalizing:
            return isActive ? "checkmark.circle.fill" : "checkmark.circle"
        }
    }

    private func linuxStageTitle(for stage: LinuxDownloadFlowStage) -> String {
        switch stage {
        case .connection:
            return String(localized: "downloader.linux.stage.connection")
        case .downloading:
            return String(localized: "downloader.linux.stage.downloading")
        case .verifying:
            return String(localized: "downloader.linux.stage.verifying")
        case .finalizing:
            return String(localized: "Kończenie pracy")
        }
    }

    private func linuxStageDescription(for stage: LinuxDownloadFlowStage) -> String? {
        let fileName = activeLinuxEntry?.fileName ?? ""
        switch stage {
        case .connection:
            return linuxDownloadFlowModel.connectionStatusText
        case .downloading:
            return String(format: String(localized: "Pobieranie pliku %@..."), fileName)
        case .verifying:
            return String(format: String(localized: "Weryfikowanie pliku %@..."), fileName)
        case .finalizing:
            return linuxDownloadFlowModel.finalizeStatusText
        }
    }

    private func linuxStageProgress(for stage: LinuxDownloadFlowStage) -> Double? {
        switch stage {
        case .downloading:
            return linuxDownloadFlowModel.downloadProgress
        case .verifying:
            return linuxDownloadFlowModel.verifyProgress
        case .connection, .finalizing:
            return nil
        }
    }
}
