import Foundation

// MARK: - ISO Entry Model

struct ISOEntry: Identifiable, Hashable {
    let id: String
    let family: String
    let name: String
    let version: String
    let description: String
    let sizeText: String
    let kind: ISOEntryKind

    /// SF Symbol name used as a fallback when no logo PNG is bundled.
    let fallbackSymbol: String

    /// Accent color for the fallback symbol (as hex string, e.g. "#E95420").
    let accentColorHex: String
}

struct ISOFamilyGroup: Identifiable, Hashable {
    let family: String
    let entries: [ISOEntry]
    var id: String { family }
}

// MARK: - Entry Kind

enum ISOEntryKind: Hashable {
    /// A direct URL to a downloadable ISO file.
    case directDownload(url: URL)
    /// Opens an external page in the default browser (e.g. Windows).
    case browserRedirect(url: URL, note: String)
}

// MARK: - Static Catalog

enum ISOCatalog {

    static let all: [ISOEntry] = [
        windowsEntry(
            id: "windows_11",
            name: "Windows 11",
            version: "24H2",
            description: "Home, Pro & Education. Requires TPM 2.0-capable hardware.",
            sizeText: "~6.2 GB"
        ),
        windowsEntry(
            id: "windows_10",
            name: "Windows 10",
            version: "22H2",
            description: "Home & Pro. Broadest hardware support.",
            sizeText: "~5.8 GB"
        ),
        ISOEntry(
            id: "ubuntu_2404",
            family: "Ubuntu",
            name: "Ubuntu",
            version: "24.04.2 LTS",
            description: "Long-Term Support. GNOME desktop. Supported until 2029.",
            sizeText: "~6.1 GB",
            kind: .directDownload(
                url: URL(string: "https://releases.ubuntu.com/24.04/ubuntu-24.04.2-desktop-amd64.iso")!
            ),
            fallbackSymbol: "circle.grid.cross.fill",
            accentColorHex: "#E95420"
        ),
        ISOEntry(
            id: "ubuntu_2204",
            family: "Ubuntu",
            name: "Ubuntu",
            version: "22.04.5 LTS",
            description: "Long-Term Support. GNOME desktop. Supported until 2027.",
            sizeText: "~5.7 GB",
            kind: .directDownload(
                url: URL(string: "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-desktop-amd64.iso")!
            ),
            fallbackSymbol: "circle.grid.cross.fill",
            accentColorHex: "#E95420"
        ),
        ISOEntry(
            id: "fedora_43_gnome",
            family: "Fedora",
            name: "Fedora Workstation (GNOME)",
            version: "43",
            description: "Latest stable Fedora with GNOME desktop.",
            sizeText: "~2.4 GB",
            kind: .directDownload(
                url: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/43/Workstation/x86_64/iso/Fedora-Workstation-Live-43-1.6.x86_64.iso")!
            ),
            fallbackSymbol: "f.circle.fill",
            accentColorHex: "#3C6EB4"
        ),
        ISOEntry(
            id: "fedora_43_kde",
            family: "Fedora",
            name: "Fedora KDE Plasma Desktop",
            version: "43",
            description: "Fedora 43 with KDE Plasma desktop environment.",
            sizeText: "~2.4 GB",
            kind: .directDownload(
                url: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/43/KDE/x86_64/iso/Fedora-KDE-Desktop-Live-43-1.6.x86_64.iso")!
            ),
            fallbackSymbol: "gearshape.2.fill",
            accentColorHex: "#1D99F3"
        ),
        ISOEntry(
            id: "debian_12",
            family: "Debian",
            name: "Debian",
            version: "12.10 (Bookworm)",
            description: "Stable. Minimal netinstall ISO. Extremely reliable.",
            sizeText: "~670 MB",
            kind: .directDownload(
                url: URL(string: "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso")!
            ),
            fallbackSymbol: "tornado",
            accentColorHex: "#D70A53"
        ),
        ISOEntry(
            id: "arch_latest",
            family: "Arch Linux",
            name: "Arch Linux",
            version: "Latest (Rolling)",
            description: "Rolling release. Minimal base install. For advanced users.",
            sizeText: "~1.2 GB",
            kind: .directDownload(
                url: URL(string: "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso")!
            ),
            fallbackSymbol: "archivebox.fill",
            accentColorHex: "#1793D1"
        ),
        ISOEntry(
            id: "cachyos_latest",
            family: "CachyOS",
            name: "CachyOS",
            version: "Latest",
            description: "Performance-optimized Arch-based distro with GNOME.",
            sizeText: "~2.8 GB",
            kind: .directDownload(
                url: URL(string: "https://mirror.cachyos.org/ISO/cachyos-gnome-linux-latest.iso")!
            ),
            fallbackSymbol: "bolt.fill",
            accentColorHex: "#8B5CF6"
        ),
    ]

    static var familyGroups: [ISOFamilyGroup] {
        var seen: [String: [ISOEntry]] = [:]
        var order: [String] = []
        for entry in all {
            if seen[entry.family] == nil {
                order.append(entry.family)
                seen[entry.family] = []
            }
            seen[entry.family]!.append(entry)
        }
        return order.compactMap { family in
            guard let entries = seen[family], !entries.isEmpty else { return nil }
            return ISOFamilyGroup(family: family, entries: entries)
        }
    }

    // MARK: - Private helpers

    private static let windowsDownloadPage11 = URL(string: "https://www.microsoft.com/software-download/windows11")!
    private static let windowsDownloadPage10 = URL(string: "https://www.microsoft.com/software-download/windows10")!

    private static let windowsNote = NSLocalizedString(
        "Microsoft wymaga odwiedzenia strony internetowej, aby pobrać obraz ISO systemu Windows. Pobierz plik ISO, a następnie otwórz go w macUSB.",
        comment: "Windows ISO download redirect note shown below the Get from Microsoft button"
    )


    private static func windowsEntry(
        id: String,
        name: String,
        version: String,
        description: String,
        sizeText: String
    ) -> ISOEntry {
        let page = (id == "windows_11") ? windowsDownloadPage11 : windowsDownloadPage10
        return ISOEntry(
            id: id,
            family: "Windows",
            name: name,
            version: version,
            description: description,
            sizeText: sizeText,
            kind: .browserRedirect(url: page, note: windowsNote),
            fallbackSymbol: "laptopcomputer",
            accentColorHex: "#0078D4"
        )
    }
}
