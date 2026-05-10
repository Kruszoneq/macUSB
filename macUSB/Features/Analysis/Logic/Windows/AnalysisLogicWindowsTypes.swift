import Foundation

enum WindowsFamily: String {
    case xp
    case vista
    case seven
    case eight
    case eightOne
    case ten
    case eleven
    case server2003
    case server2008R2
    case server2012
    case server2012R2
    case server2016
    case server2019
    case server2022
    case server2025

    var displayPrefix: String {
        isServerFamily ? "Windows Server" : "Windows"
    }

    var displayVersionLabel: String {
        switch self {
        case .xp: return "XP"
        case .vista: return "Vista"
        case .seven: return "7"
        case .eight: return "8"
        case .eightOne: return "8.1"
        case .ten: return "10"
        case .eleven: return "11"
        case .server2003: return "2003"
        case .server2008R2: return "2008 R2"
        case .server2012: return "2012"
        case .server2012R2: return "2012 R2"
        case .server2016: return "2016"
        case .server2019: return "2019"
        case .server2022: return "2022"
        case .server2025: return "2025"
        }
    }

    var isServerFamily: Bool {
        switch self {
        case .server2003, .server2008R2, .server2012, .server2012R2, .server2016, .server2019, .server2022, .server2025:
            return true
        case .xp, .vista, .seven, .eight, .eightOne, .ten, .eleven:
            return false
        }
    }

    var supportsWorkflow: Bool {
        switch self {
        case .eight, .eightOne, .ten, .eleven:
            return true
        case .server2012, .server2012R2, .server2016, .server2019, .server2022, .server2025:
            return true
        case .xp, .vista, .seven, .server2003, .server2008R2:
            return false
        }
    }
}

enum WindowsArchitecture: String {
    case x86
    case arm
    case unknown
}

struct WindowsEFIStatus {
    let hasEFI: Bool
    let evidence: [String]
}

enum WindowsSupportReason: String {
    case supported
    case unsupportedFamily
    case missingEFI
    case unsupportedFamilyAndMissingEFI
}

struct WindowsDetectionResult {
    let family: WindowsFamily
    let servicePack: String?
    let arch: WindowsArchitecture
    let isARM: Bool
    let displayName: String
    let isSupported: Bool
    let supportReason: WindowsSupportReason
    let efiStatus: WindowsEFIStatus
    let evidence: [String]
}

struct WindowsImageMetadata {
    let volumeName: String
    let buildBranch: String?
    let buildArchRaw: String?
    let hasI386: Bool
    let win51Markers: [String]
    let hasInstallWIM: Bool
    let hasInstallESD: Bool
    let hasInstallSWM: Bool
    let cversionMinClient: String?
    let cversionMinServer: String?
    let sourceFileName: String
    let efiStatus: WindowsEFIStatus
    let evidence: [String]

    var hasInstallImage: Bool {
        hasInstallWIM || hasInstallESD || hasInstallSWM
    }
}
