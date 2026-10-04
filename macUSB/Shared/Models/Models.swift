import SwiftUI

// Definicja zakładek w menu
enum SidebarItem: Hashable {
    case start
    case bootableUSB
    case info
}

/// Wykryty standard/wersja USB dla nośnika
enum USBPortSpeed: String, Equatable {
    case usb2 = "USB 2.0"
    case usb3 = "USB 3.0"
    case usb31 = "USB 3.1"
    case usb32 = "USB 3.2"
    case usb4 = "USB 4.0"
    case unknown = "USB"

    var isUSB2: Bool { self == .usb2 }
}

/// Physical target kind, independent of the reader's USB port speed.
enum USBTargetMediaKind: String, Hashable {
    case usb = "USB"
    case sdCard = "SD CARD"

    static func from(busProtocol: String?) -> Self? {
        switch busProtocol?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "USB": return .usb
        case "SECURE DIGITAL": return .sdCard
        default: return nil
        }
    }
}

/// Wykryty schemat partycji dla nośnika
enum PartitionScheme: String, Equatable {
    case gpt = "GPT"
    case apm = "APM"
    case mbr = "MBR"
    case unknown = "Unknown"
}

/// Wykryty format systemu plików na woluminie
enum FileSystemFormat: String, Equatable {
    case apfs = "APFS"
    case hfsPlus = "HFS+"
    case exfat = "exFAT"
    case fat = "FAT"
    case ntfs = "NTFS"
    case unknown = "Unknown"
}

// Struktura pomocnicza dla dysków USB
struct USBDrive: Hashable, Identifiable {
    let name: String
    let device: String  // np. disk2s1
    let size: String    // np. 16 GB
    let url: URL
    let usbSpeed: USBPortSpeed?
    let mediaKind: USBTargetMediaKind
    let partitionScheme: PartitionScheme?
    let fileSystemFormat: FileSystemFormat?
    let needsFormatting: Bool
    
    init(
        name: String,
        device: String,
        size: String,
        url: URL,
        usbSpeed: USBPortSpeed? = nil,
        mediaKind: USBTargetMediaKind = .usb,
        partitionScheme: PartitionScheme? = nil,
        fileSystemFormat: FileSystemFormat? = nil,
        needsFormatting: Bool? = nil
    ) {
        self.name = name
        self.device = device
        self.size = size
        self.url = url
        self.usbSpeed = usbSpeed
        self.mediaKind = mediaKind
        self.partitionScheme = partitionScheme
        self.fileSystemFormat = fileSystemFormat

        let computedRequiresFormatting = !(partitionScheme == .gpt && fileSystemFormat == .hfsPlus)
        self.needsFormatting = needsFormatting ?? computedRequiresFormatting
    }
    
    // Format wyświetlania: disk1s1 - 16GB - SANDISK
    var displayName: String {
        return "\(device) - \(size) - \(mediaDisplayName) - \(name)"
    }

    /// Hardware labels are verbatim, like the existing USB version labels.
    var mediaDisplayName: String {
        mediaKind == .sdCard ? mediaKind.rawValue : (usbSpeed?.rawValue ?? "USB")
    }

    var wholeDiskDisplayName: String { "\(device) - \(size) - \(mediaDisplayName)" }
    
    /// Czy nośnik pracuje w standardzie USB 2.0
    var isUSB2: Bool { mediaKind == .usb && usbSpeed?.isUSB2 == true }

    /// Czy wybór reprezentuje fizyczny whole-disk (`diskX`), a nie zamontowany wolumin.
    var isWholeDiskTarget: Bool {
        device == USBDriveLogic.wholeDiskName(from: device)
            && url.path == "/dev/\(device)"
    }

    /// Stabilny identyfikator nośnika używany przez Picker i synchronizację wyboru.
    var selectionID: String { url.absoluteString }

    var id: String { selectionID }
}
