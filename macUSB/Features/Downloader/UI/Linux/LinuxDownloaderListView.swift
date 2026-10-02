import SwiftUI
import AppKit

extension MacOSDownloaderWindowShellView {
    var linuxImageSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(String(localized: "downloader.linux.list.title"))
                    .font(.headline)

                Spacer()

                Button {
                    selectedLinuxImageID = nil
                    linuxLogic.startDiscovery(destinationDirectoryURL: linuxDestinationDirectoryURL)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .macUSBSecondaryButtonStyle()
                .disabled(isLinuxDiscoveryInProgress)
                .opacity(isLinuxDiscoveryInProgress ? 0.65 : 1.0)
                .help(String(localized: "downloader.linux.list.refresh_help"))

                Button {
                    isLinuxOptionsPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text(String(localized: "Opcje"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .macUSBSecondaryButtonStyle()
                .disabled(isLinuxDiscoveryInProgress)
                .opacity(isLinuxDiscoveryInProgress ? 0.65 : 1.0)
            }

            linuxImageListArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var isLinuxDiscoveryInProgress: Bool {
        switch linuxLogic.state {
        case .idle, .loading:
            return true
        case .cancelled, .failed, .loaded:
            return false
        }
    }

    private var linuxImageListArea: some View {
        ZStack(alignment: .topLeading) {
            if isLinuxDiscoveryInProgress {
                linuxDiscoveryStatusView
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                linuxPostDiscoveryContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isLinuxDiscoveryInProgress)
        .padding(MacUSBDesignTokens.panelInnerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macUSBPanelSurface(.neutral)
        .clipped()
    }

    @ViewBuilder
    private var linuxPostDiscoveryContent: some View {
        switch linuxLogic.state {
        case .cancelled:
            if linuxLogic.distributionGroups.isEmpty {
                listMessageView(
                    title: String(localized: "Wyszukiwanie anulowane"),
                    description: String(localized: "downloader.linux.list.cancelled_message")
                )
            } else {
                linuxDistributionSectionsView
            }
        case .failed:
            linuxDiscoveryFailureView
        case .loaded:
            if visibleLinuxDistributionGroups.isEmpty {
                listMessageView(
                    title: String(localized: "Brak dostępnych systemów"),
                    description: String(localized: "downloader.linux.list.empty_message")
                )
            } else {
                linuxDistributionSectionsView
            }
        case .idle, .loading:
            EmptyView()
        }
    }

    private var linuxDiscoveryStatusView: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)

                Text(String(localized: "Wyszukiwanie dostępnych systemów"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                Spacer()
                    .frame(height: 10)

                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 360)

                Text(String(localized: "downloader.linux.discovery.status"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .macUSBPanelSurface(.subtle)
    }

    private var linuxDiscoveryFailureView: some View {
        let isOffline = isLinuxDiscoveryOfflineFailure()
        let title = isOffline
            ? String(localized: "Połączenie internetowe jest niedostępne")
            : String(localized: "downloader.linux.discovery.failed_title")
        let description = isOffline
            ? String(localized: "Sprawdzanie dostępnych systemów zostało wstrzymane. Po przywróceniu połączenia ponów próbę odświeżenia.")
            : String(localized: "downloader.linux.discovery.failed_message")

        return linuxWarningCard(title: title, description: description)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func isLinuxDiscoveryOfflineFailure() -> Bool {
        guard let errorText = linuxLogic.errorText?.lowercased() else { return false }
        let offlineMarkers = [
            "not connected to internet",
            "network connection was lost",
            "cannot find host",
            "cannot connect to host",
            "połączenie internetowe",
            "połączenie z internetem",
            "brak połączenia"
        ]
        return offlineMarkers.contains { errorText.contains($0) }
    }

    private func linuxWarningCard(title: String, description: String) -> some View {
        StatusCard(tone: .warning, density: .compact) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var linuxDistributionSectionsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !linuxLogic.unavailableSources.isEmpty {
                    linuxWarningCard(
                        title: String(localized: "downloader.linux.discovery.partial_title"),
                        description: String(
                            format: String(localized: "downloader.linux.discovery.partial_message"),
                            ListFormatter.localizedString(
                                byJoining: linuxLogic.unavailableSources.map(\.displayName)
                            )
                        )
                    )
                }

                ForEach(visibleLinuxDistributionGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.distribution.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(group.entries) { entry in
                            linuxImageRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func linuxImageRow(_ entry: LinuxImageEntry) -> some View {
        let isSelected = selectedLinuxImageID == entry.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                linuxDistributionIconView(for: entry.distribution)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(entry.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)

                        linuxDownloadedBadge(for: entry)
                    }

                    Text(linuxEntrySecondaryText(for: entry))
                        .font(.caption2.italic())
                        .foregroundStyle(.secondary)
                }
                .textSelection(.disabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)

            if isSelected {
                HStack {
                    Spacer()

                    Button {
                        handleLinuxDownloadTap(for: entry)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(String(localized: "Pobierz"))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .macUSBPrimaryButtonStyle()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .macUSBPanelSurface(isSelected ? .active : .subtle)
        .overlay(
            RoundedRectangle(
                cornerRadius: MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode()),
                style: .continuous
            )
            .stroke(Color.accentColor.opacity(isSelected ? 0.55 : 0), lineWidth: 1.1)
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: MacUSBDesignTokens.panelCornerRadius(for: currentVisualMode()),
                style: .continuous
            )
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedLinuxImageID = selectedLinuxImageID == entry.id ? nil : entry.id
            }
        }
    }

    func linuxEntrySecondaryText(for entry: LinuxImageEntry) -> String {
        [entry.architecture.displayName, entry.sizeText]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    var visibleLinuxDistributionGroups: [LinuxDistributionGroup] {
        linuxLogic.distributionGroups.compactMap { group in
            var entries = group.entries.filter { entry in
                linuxShowARMImages || entry.architecture == .x86_64
            }
            if !linuxShowAllVersions {
                // Groups are sorted newest-first, so the first entry of each line is its newest version.
                var seenLines: Set<String> = []
                entries = entries.filter { seenLines.insert($0.lineKey).inserted }
            }
            guard !entries.isEmpty else { return nil }
            return LinuxDistributionGroup(distribution: group.distribution, entries: entries)
        }
    }

    func ensureSelectedLinuxImageIsVisible() {
        guard let selectedLinuxImageID else { return }
        let visibleIDs = Set(visibleLinuxDistributionGroups.flatMap { $0.entries.map(\.id) })
        if !visibleIDs.contains(selectedLinuxImageID) {
            self.selectedLinuxImageID = nil
        }
    }

    @ViewBuilder
    func linuxDistributionIconView(for distribution: LinuxDistribution) -> some View {
        if let image = loadLinuxDistributionIcon(named: distribution.iconResourceName)
            ?? loadLinuxDistributionIcon(named: "linux") {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
        } else {
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
        }
    }

    private func loadLinuxDistributionIcon(named name: String) -> NSImage? {
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Icons/Linux/Distros")
            ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Distros")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        return url.flatMap { NSImage(contentsOf: $0) }
    }

    @ViewBuilder
    private func linuxDownloadedBadge(for entry: LinuxImageEntry) -> some View {
        if entry.isDownloaded {
            Text(String(localized: "downloader.local_installers.downloaded_badge"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.accentColor.opacity(0.46), lineWidth: 0.7)
                )
        }
    }

    func handleLinuxDownloadTap(for entry: LinuxImageEntry) {
        if entry.isDownloaded {
            guard presentLinuxRedownloadConfirmationAlert() else {
                AppLogging.info(
                    "Redownload of existing image \(entry.fileName) cancelled.",
                    stage: .downloader, workflow: .linux
                )
                return
            }
        }

        withAnimation(MacUSBDesignTokens.stageTransitionAnimation) {
            activeLinuxEntry = entry
        }
        linuxDownloadFlowModel.start(for: entry, destinationDirectoryURL: linuxDestinationDirectoryURL)
    }
}
