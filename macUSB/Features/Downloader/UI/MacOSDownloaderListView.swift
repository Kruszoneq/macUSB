import SwiftUI
import AppKit

extension MacOSDownloaderWindowShellView {
    var installerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Lista systemów dostępnych do pobrania")
                    .font(.headline)

                Spacer()

                Button {
                    isOptionsPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Opcje")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .macUSBSecondaryButtonStyle()
                .disabled(isDiscoveryInProgress)
                .opacity(isDiscoveryInProgress ? 0.65 : 1.0)
            }

            installerListArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var isDiscoveryInProgress: Bool {
        switch logic.state {
        case .idle, .loading:
            return true
        case .cancelled, .failed, .loaded:
            return false
        }
    }

    var installerListArea: some View {
        ZStack(alignment: .topLeading) {
            if isDiscoveryInProgress {
                discoveryStatusView
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                postDiscoveryContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isDiscoveryInProgress)
        .padding(MacUSBDesignTokens.panelInnerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macUSBPanelSurface(.neutral)
        .clipped()
    }

    @ViewBuilder
    var postDiscoveryContent: some View {
        switch logic.state {
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
        case .idle, .loading:
            EmptyView()
        }
    }

    var discoveryStatusView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(9)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sprawdzanie wersji macOS")
                        .font(.headline)
                    Text("Łączę się z serwerami Apple i wykrywam dostępne instalatory...")
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
            .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macUSBPanelSurface(.subtle)
    }

    var installerSectionsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(visibleFamilyGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.family)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(group.entries) { entry in
                            installerEntryRow(entry)
                        }
                    }
                }
            }
        }
    }

    func installerEntryRow(_ entry: MacOSInstallerEntry) -> some View {
        let isSelected = selectedInstallerID == entry.id
        let supportsMontereyDownload = supportsMontereyDownload(entry)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                installerIconView(for: entry)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(entry.name) \(entry.version)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    if let secondaryText = entrySecondaryText(for: entry) {
                        Text(secondaryText)
                            .font(.caption2.italic())
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.disabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)

            if isSelected {
                HStack {
                    Spacer()

                    Button {
                        handleDownloadTap(for: entry)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Pobierz")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .macUSBPrimaryButtonStyle()
                    .disabled(!supportsMontereyDownload)
                    .opacity(supportsMontereyDownload ? 1 : 0.6)
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
                if selectedInstallerID == entry.id {
                    selectedInstallerID = nil
                } else {
                    selectedInstallerID = entry.id
                }
            }
        }
    }

    var visibleFamilyGroups: [MacOSInstallerFamilyGroup] {
        guard !showAllAvailableVersions else {
            return logic.familyGroups
        }

        return logic.familyGroups.compactMap { group in
            guard let newest = group.entries.first else {
                return nil
            }
            return MacOSInstallerFamilyGroup(family: group.family, entries: [newest])
        }
    }

    @ViewBuilder
    func installerIconView(for entry: MacOSInstallerEntry) -> some View {
        if let image = resolveInstallerIcon(for: entry) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
        }
    }

    func resolveInstallerIcon(for entry: MacOSInstallerEntry) -> NSImage? {
        let versionKey = normalizedVersionKey(from: entry.version)
        let majorVersionKey = normalizedMajorVersionKey(from: entry.version)
        let nameKey = normalizedSystemNameKey(from: entry.name)
        let nameAliases = iconNameAliases(for: nameKey)

        for alias in nameAliases {
            if let image = loadIcon(named: "os_\(versionKey)_\(alias)") {
                return image
            }
            if let image = loadIcon(named: "os_\(majorVersionKey)_\(alias)") {
                return image
            }
        }

        let iconPaths = Bundle.main.paths(forResourcesOfType: "icns", inDirectory: "Icons/OS")
            + Bundle.main.paths(forResourcesOfType: "icns", inDirectory: nil)

        let fileNames = iconPaths.map({ URL(fileURLWithPath: $0).lastPathComponent })
        for alias in nameAliases {
            if let fileName = fileNames.first(where: {
                matchesMajorVersionIconFile($0, majorVersionKey: majorVersionKey, alias: alias)
            }), let image = loadIcon(named: String(fileName.dropLast(".icns".count))) {
                return image
            }
        }

        return nil
    }

    func loadIcon(named resourceName: String) -> NSImage? {
        if let nestedURL = Bundle.main.url(forResource: resourceName, withExtension: "icns", subdirectory: "Icons/OS") {
            return NSImage(contentsOf: nestedURL)
        }
        if let rootURL = Bundle.main.url(forResource: resourceName, withExtension: "icns") {
            return NSImage(contentsOf: rootURL)
        }
        return nil
    }

    func normalizedVersionKey(from version: String) -> String {
        let parts = version.split(separator: ".")
        guard let major = parts.first else { return version.replacingOccurrences(of: ".", with: "_") }

        if parts.count >= 2 {
            return "\(major)_\(parts[1])"
        }
        return String(major)
    }

    func normalizedMajorVersionKey(from version: String) -> String {
        let major = version.split(separator: ".").first ?? Substring(version)
        return String(major)
    }

    func normalizedSystemNameKey(from name: String) -> String {
        let stripped = name.replacingOccurrences(
            of: #"^(Install\s+)?(Mac\s+OS\s+X|OS\s+X|macOS)\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .lowercased()

        let components = stripped.split { !$0.isLetter && !$0.isNumber }
        return components.joined(separator: "_")
    }

    func iconNameAliases(for key: String) -> [String] {
        if key == "mavericks" {
            return ["mavericks", "maverics"]
        }
        return [key]
    }

    func shouldShowBuild(_ build: String) -> Bool {
        let trimmed = build.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.caseInsensitiveCompare("N/A") != .orderedSame
    }

    func entrySecondaryText(for entry: MacOSInstallerEntry) -> String? {
        let sizeText = entry.installerSizeText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSize = (sizeText?.isEmpty == false) ? sizeText : nil
        let buildText = shouldShowBuild(entry.build) ? entry.build : nil

        switch (normalizedSize, buildText) {
        case let (.some(size), .some(build)):
            return "\(size) - \(build)"
        case let (.some(size), nil):
            return size
        case let (nil, .some(build)):
            return build
        case (nil, nil):
            return nil
        }
    }

    func matchesMajorVersionIconFile(_ fileName: String, majorVersionKey: String, alias: String) -> Bool {
        guard fileName.hasPrefix("os_"), fileName.hasSuffix(".icns") else { return false }

        let core = String(fileName.dropFirst(3).dropLast(".icns".count))
        let components = core.split(separator: "_")
        guard let first = components.first, first == Substring(majorVersionKey) else { return false }

        let nameStartIndex: Int
        if components.count > 1, Int(components[1]) != nil {
            nameStartIndex = 2
        } else {
            nameStartIndex = 1
        }

        guard components.count > nameStartIndex else { return false }
        let parsedAlias = components[nameStartIndex...].joined(separator: "_")
        return parsedAlias == alias
    }

    func listMessageView(title: String, description: String) -> some View {
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
}
