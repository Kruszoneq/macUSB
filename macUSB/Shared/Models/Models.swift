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
    let id = UUID()
    let name: String
    let device: String  // np. disk2s1
    let size: String    // np. 16 GB
    let url: URL
    let usbSpeed: USBPortSpeed?
    let partitionScheme: PartitionScheme?
    let fileSystemFormat: FileSystemFormat?
    let requiresFormattingInNextStages: Bool
    
    init(
        name: String,
        device: String,
        size: String,
        url: URL,
        usbSpeed: USBPortSpeed? = nil,
        partitionScheme: PartitionScheme? = nil,
        fileSystemFormat: FileSystemFormat? = nil,
        requiresFormattingInNextStages: Bool? = nil
    ) {
        self.name = name
        self.device = device
        self.size = size
        self.url = url
        self.usbSpeed = usbSpeed
        self.partitionScheme = partitionScheme
        self.fileSystemFormat = fileSystemFormat

        let computedRequiresFormatting = !(partitionScheme == .gpt && fileSystemFormat == .hfsPlus)
        self.requiresFormattingInNextStages = requiresFormattingInNextStages ?? computedRequiresFormatting
    }
    
    // Format wyświetlania: disk1s1 - 16GB - SANDISK
    var displayName: String {
        let speedText = usbSpeed?.rawValue ?? "USB"
        return "\(device) - \(size) - \(speedText) - \(name)"
    }
    
    /// Czy nośnik pracuje w standardzie USB 2.0
    var isUSB2: Bool { usbSpeed?.isUSB2 == true }
}
