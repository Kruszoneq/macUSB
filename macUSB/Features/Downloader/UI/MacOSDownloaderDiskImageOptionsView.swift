import SwiftUI
import AppKit

struct MacOSDownloaderDiskImageOptionsView: View {
    @Binding var showAllAvailableVersions: Bool
    @Binding var showBetaVersions: Bool
    @Binding var createDiskImage: Bool
    @Binding var diskImageDestinationDirectoryURL: URL?
    @Binding var preserveDownloadedFilesInDebug: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Opcje pobierania"))
                .font(.headline)

            Toggle(String(localized: "Pokaż wszystkie wersje"), isOn: $showAllAvailableVersions)
                .toggleStyle(.checkbox)

            Toggle(
                String(localized: "downloader.options.showBetaVersions"),
                isOn: $showBetaVersions
            )
            .toggleStyle(.checkbox)

            Toggle(isOn: diskImageToggleBinding) {
                Text("downloader.disk_image.option.title")
            }
            .toggleStyle(.checkbox)

            if createDiskImage, let diskImageDestinationDirectoryURL {
                HStack(spacing: 10) {
                    Text(abbreviatedDestination(diskImageDestinationDirectoryURL))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(diskImageDestinationDirectoryURL.path)

                    Spacer(minLength: 8)

                    Button {
                        chooseDiskImageDestination(isInitialSelection: false)
                    } label: {
                        Text("downloader.disk_image.folder.change")
                    }
                    .macUSBSecondaryButtonStyle()
                    .help(String(localized: "downloader.disk_image.folder.change_help"))
                }
                .padding(.leading, 22)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            #if DEBUG
            HStack(spacing: 10) {
                Capsule()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(height: 1)
                Text(String(localized: "Deweloperskie"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Capsule()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(height: 1)
            }
            .padding(.vertical, 2)

            Toggle(String(localized: "Zachowaj pobrane pliki (Debug)"), isOn: $preserveDownloadedFilesInDebug)
                .toggleStyle(.checkbox)
            #endif

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "OK"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .macUSBPrimaryButtonStyle()
            }
        }
        .animation(.easeInOut(duration: 0.24), value: createDiskImage)
        .padding(18)
        .frame(width: 420, height: 300)
    }

    private var diskImageToggleBinding: Binding<Bool> {
        Binding(
            get: { createDiskImage },
            set: { newValue in
                if newValue {
                    chooseDiskImageDestination(isInitialSelection: true)
                } else {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        createDiskImage = false
                    }
                }
            }
        )
    }

    private func chooseDiskImageDestination(isInitialSelection: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = String(localized: "downloader.disk_image.picker.title")
        panel.message = String(localized: "downloader.disk_image.picker.message")
        panel.prompt = String(localized: "downloader.disk_image.picker.prompt")
        if let diskImageDestinationDirectoryURL {
            panel.directoryURL = diskImageDestinationDirectoryURL
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            if isInitialSelection, diskImageDestinationDirectoryURL == nil {
                createDiskImage = false
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.24)) {
            diskImageDestinationDirectoryURL = selectedURL.standardizedFileURL
            createDiskImage = true
        }
    }

    private func abbreviatedDestination(_ url: URL) -> String {
        let lastComponent = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return "…/\(lastComponent)"
    }
}
