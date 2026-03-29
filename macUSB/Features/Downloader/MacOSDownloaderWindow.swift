import SwiftUI
import AppKit

@MainActor
final class MacOSDownloaderWindowManager {
    static let shared = MacOSDownloaderWindowManager()
    private let downloaderWindowHeight: CGFloat = 650

    private var sheetWindow: NSWindow?

    private init() {}

    func present() {
        if let sheetWindow {
            sheetWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
            AppLogging.error(
                "Nie mozna otworzyc okna downloadera: brak aktywnego okna macUSB.",
                category: "Downloader"
            )
            return
        }

        let sheetContentHeight = downloaderWindowHeight

        let contentView = MacOSDownloaderWindowView(contentHeight: sheetContentHeight) { [weak self] in
            self?.close()
        }
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        let fixedSize = NSSize(
            width: MacUSBDesignTokens.windowWidth,
            height: sheetContentHeight
        )

        window.styleMask = [.titled]
        window.title = String(localized: "Menedżer pobierania systemów macOS")
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.isReleasedWhenClosed = false
        window.center()

        sheetWindow = window
        parentWindow.beginSheet(window)

        AppLogging.info(
            "Otwarto okno menedzera pobierania systemow macOS.",
            category: "Downloader"
        )
    }

    func close() {
        guard let window = sheetWindow else { return }

        if let parent = window.sheetParent {
            parent.endSheet(window)
            parent.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
        }

        sheetWindow = nil
        NSApp.activate(ignoringOtherApps: true)

        AppLogging.info(
            "Zamknieto okno menedzera pobierania systemow macOS.",
            category: "Downloader"
        )
    }
}

struct MacOSDownloaderWindowView: View {
    let contentHeight: CGFloat
    let onClose: () -> Void

    @StateObject private var logic = MacOSDownloaderLogic()

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: MacUSBDesignTokens.sectionGroupSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Menedżer pobierania macOS")
                        .font(.title3.weight(.semibold))
                    Text("Lista oficjalnych instalatorów macOS i OS X dostępnych na serwerach Apple.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MacUSBDesignTokens.panelInnerPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .macUSBPanelSurface(.subtle)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Dostępne systemy do pobrania")
                        .font(.headline)

                    installerListArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(MacUSBDesignTokens.panelInnerPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .macUSBPanelSurface(.subtle)
            }
            .padding(.horizontal, MacUSBDesignTokens.contentHorizontalPadding)
            .padding(.top, MacUSBDesignTokens.contentVerticalPadding)
            .frame(
                width: MacUSBDesignTokens.windowWidth,
                height: contentHeight,
                alignment: .topLeading
            )
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    Button {
                        logic.cancelDiscovery()
                        onClose()
                    } label: {
                        HStack {
                            Text("Zamknij")
                            Image(systemName: "xmark.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                    }
                    .macUSBPrimaryButtonStyle()
                }
            }

            if logic.isLoading {
                discoveryOverlay
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .task {
            logic.startDiscovery()
        }
        .onDisappear {
            logic.cancelDiscovery(updateState: false)
        }
    }

    private var installerListArea: some View {
        Group {
            switch logic.state {
            case .idle, .loading:
                listMessageView(
                    title: String(localized: "Oczekiwanie na wyniki"),
                    description: String(localized: "Trwa sprawdzanie dostępnych wersji.")
                )
            case .cancelled:
                if logic.familyGroups.isEmpty {
                    listMessageView(
                        title: String(localized: "Sprawdzanie anulowane"),
                        description: String(localized: "Otwórz downloader ponownie, aby uruchomić nowe sprawdzanie.")
                    )
                } else {
                    installerSectionsView
                }
            case .failed:
                listMessageView(
                    title: String(localized: "Nie udało się pobrać listy"),
                    description: logic.errorText ?? String(localized: "Wystąpił błąd połączenia z serwerami Apple.")
                )
            case .loaded:
                if logic.familyGroups.isEmpty {
                    listMessageView(
                        title: String(localized: "Brak dostępnych wersji"),
                        description: String(localized: "Nie znaleziono publicznych instalatorów w aktualnym katalogu Apple.")
                    )
                } else {
                    installerSectionsView
                }
            }
        }
        .padding(MacUSBDesignTokens.panelInnerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macUSBPanelSurface(.neutral)
    }

    private var installerSectionsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(logic.familyGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.family)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(group.entries) { entry in
                            Text(entry.displayTitle)
                                .font(.subheadline)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .macUSBPanelSurface(.subtle)
                        }
                    }
                }
            }
        }
    }

    private func listMessageView(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var discoveryOverlay: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(9)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sprawdzanie wersji macOS")
                            .font(.headline)
                        Text("Łączę się z serwerami Apple i wykrywam dostępne instalatory.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ProgressView()
                    .progressViewStyle(.linear)

                if !logic.statusText.isEmpty {
                    Text(logic.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    logic.cancelDiscovery()
                } label: {
                    Text("Anuluj")
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
                .macUSBSecondaryButtonStyle()
            }
            .padding(16)
            .frame(width: 420)
            .macUSBPanelSurface(.neutral)
            .shadow(color: Color.black.opacity(0.20), radius: 16, x: 0, y: 8)
        }
    }
}
