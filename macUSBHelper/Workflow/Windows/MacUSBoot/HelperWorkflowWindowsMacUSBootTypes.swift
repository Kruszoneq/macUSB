import Foundation

enum HelperWorkflowWindowsMacUSBootFailure: Error {
    case invalidArtifact(String)
    case targetAccess(String)
    case incompatibleLayout(String)
    case unsafeOccupiedGap(String)
    case stageTwoWrite(String)
    case stageTwoSynchronization(String)
    case stageTwoReadback(String)
    case mbrWrite(String)
    case mbrSynchronization(String)
    case mbrReadback(String)

    var diagnosticDescription: String {
        switch self {
        case .invalidArtifact(let detail): return "macusboot_invalid_artifact: \(detail)"
        case .targetAccess(let detail): return "macusboot_target_access: \(detail)"
        case .incompatibleLayout(let detail): return "macusboot_incompatible_layout: \(detail)"
        case .unsafeOccupiedGap(let detail): return "macusboot_unsafe_occupied_gap: \(detail)"
        case .stageTwoWrite(let detail): return "macusboot_stage_two_write: \(detail)"
        case .stageTwoSynchronization(let detail): return "macusboot_stage_two_sync: \(detail)"
        case .stageTwoReadback(let detail): return "macusboot_stage_two_readback: \(detail)"
        case .mbrWrite(let detail): return "macusboot_mbr_write: \(detail)"
        case .mbrSynchronization(let detail): return "macusboot_mbr_sync: \(detail)"
        case .mbrReadback(let detail): return "macusboot_mbr_readback: \(detail)"
        }
    }
}

struct HelperWorkflowWindowsMacUSBootArtifact {
    let productVersion: String
    let binaryFileName: String
    let completeSize: Int
    let completeSHA256: String
    let mbrPayload: Data
    let stageTwo: Data
}

struct HelperWorkflowWindowsMacUSBootDiskSnapshot {
    let mbr: Data
    let gap: Data
    let blockCount: UInt64
}
