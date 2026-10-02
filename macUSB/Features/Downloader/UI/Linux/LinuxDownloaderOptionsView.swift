import SwiftUI
import AppKit

enum LinuxDownloaderDefaults {
    static var destinationDirectoryURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }
}

struct LinuxDownloaderOptionsView: View {
    @Binding var showAllVersions: Bool
    @Binding var showARMImages: Bool
    @Binding var destinationDirectoryURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Opcje pobierania"))
                .font(.headline)

            Toggle(String(localized: "Pokaż wszystkie wersje"), isOn: $showAllVersions)
                .toggleStyle(.checkbox)

            Toggle(String(localized: "downloader.linux.options.show_arm"), isOn: $showARMImages)
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "downloader.linux.options.destination"))

                HStack(spacing: 10) {
                    Text((destinationDirectoryURL.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(destinationDirectoryURL.path)

                    Spacer(minLength: 8)

                    Button {
                        chooseDestinationDirectory()
                    } label: {
                        Text("downloader.disk_image.folder.change")
                    }
                    .macUSBSecondaryButtonStyle()
                    .help(String(localized: "downloader.linux.options.destination_help"))
                }
            }

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
        .padding(18)
        .frame(width: 420, height: 260)
    }

    private func chooseDestinationDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = String(localized: "downloader.linux.picker.title")
        panel.message = String(localized: "downloader.linux.picker.message")
        panel.prompt = String(localized: "downloader.disk_image.picker.prompt")
        panel.directoryURL = destinationDirectoryURL

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        destinationDirectoryURL = selectedURL.standardizedFileURL
        AppLogging.info(
            "Linux download destination folder changed to \(destinationDirectoryURL.path).",
            stage: .downloader, workflow: .linux
        )
    }
}
