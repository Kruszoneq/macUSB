import Foundation

enum FullDiskAccessStatus: String {
    case granted
    case denied
    case unknown

    var hasConfirmedAccess: Bool {
        self == .granted
    }
}

enum FullDiskAccessCheckTrigger: String {
    case startup
    case activation
    case installationSummary
    case settingsPanel
}

enum FullDiskAccessProbeIdentifier: String {
    case timeMachine
    case mail
    case messages
    case safari
    case homeKit
}

enum FullDiskAccessProbeOperation: String {
    case readFile
    case listDirectory
}

enum FullDiskAccessProbeSignal: String {
    case granted
    case denied
    case unknown
}

struct FullDiskAccessProbeResult {
    let identifier: FullDiskAccessProbeIdentifier
    let path: String
    let operation: FullDiskAccessProbeOperation
    let signal: FullDiskAccessProbeSignal
    let errnoCode: Int32?
    let errorDescription: String?
}

struct FullDiskAccessEvaluation {
    let status: FullDiskAccessStatus
    let results: [FullDiskAccessProbeResult]
}
