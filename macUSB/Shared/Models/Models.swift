import SwiftUI

// Definicja zakładek w menu
enum SidebarItem: Hashable {
    case start
    case bootableUSB
    case info
}

// Struktura pomocnicza dla dysków USB
struct USBDrive: Hashable, Identifiable {
    let id = UUID()
    let name: String
    let device: String  // np. disk2s1
    let size: String    // np. 16 GB
    let url: URL
    
    // Format wyświetlania: disk1s1 - 16GB - SANDISK
    var displayName: String {
        "\(device) - \(size) - \(name)"
    }
}
