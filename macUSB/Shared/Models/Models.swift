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

// Struktura pomocnicza dla dysków USB
struct USBDrive: Hashable, Identifiable {
    let id = UUID()
    let name: String
    let device: String  // np. disk2s1
    let size: String    // np. 16 GB
    let url: URL
    let usbSpeed: USBPortSpeed?
    
    init(name: String, device: String, size: String, url: URL, usbSpeed: USBPortSpeed? = nil) {
        self.name = name
        self.device = device
        self.size = size
        self.url = url
        self.usbSpeed = usbSpeed
    }
    
    // Format wyświetlania: disk1s1 - 16GB - SANDISK
    var displayName: String {
        let speedText = usbSpeed?.rawValue ?? "USB"
        return "\(device) - \(size) - \(speedText) - \(name)"
    }
    
    /// Czy nośnik pracuje w standardzie USB 2.0
    var isUSB2: Bool { usbSpeed?.isUSB2 == true }
}

