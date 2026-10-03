import Foundation

enum USBDiscoveryProblem: Error, Equatable {
    case query(USBDiscoveryProcessRunner.Failure)
    case malformedData
    case incompleteData
    case capacityUnavailable
    case identityUnavailable
    case identityChanged
    case targetMissing

    var descriptionKey: String {
        switch self {
        case .query(.timedOut): return "analysis.usb.discovery.timeout.description"
        case .query(.busy), .query(.cancelled): return "analysis.usb.discovery.waiting.description"
        case .query(.launchFailed), .query(.readFailed): return "analysis.usb.discovery.process.description"
        case .query(.outputLimit), .malformedData, .incompleteData: return "analysis.usb.discovery.data.description"
        case .query(.exitStatus): return "analysis.usb.discovery.device.description"
        case .capacityUnavailable: return "analysis.usb.discovery.capacity.description"
        case .identityUnavailable, .identityChanged: return "analysis.usb.discovery.identity.description"
        case .targetMissing: return "analysis.usb.discovery.missing.description"
        }
    }
}

struct USBDiscoveryIssue: Equatable {
    let device: String
    let problem: USBDiscoveryProblem
}

struct USBTargetVerification: Equatable {
    let identity: String?
    let capacity: Result<Int64, USBDiscoveryProblem>

    var problem: USBDiscoveryProblem? {
        if case .failure(let problem) = capacity { return problem }
        return identity == nil ? .identityUnavailable : nil
    }
}

struct USBDiscoverySnapshot {
    let physicalDrives: [USBDrive]
    let optionDrives: [USBDrive]
    let verification: [String: USBTargetVerification]
    let issues: [USBDiscoveryIssue]
    let allowExternalDrives: Bool
}

struct USBAdmissionRequest: Equatable {
    let id: UUID
    var isCancelled = false
}

enum USBDiscoveryResult {
    case complete(USBDiscoverySnapshot)
    case partial(USBDiscoverySnapshot)
    case failed(USBDiscoveryProblem)
    case busy
    case cancelled
}

/// Presentation cache, discovery validity and activity belong to one state.
/// Only a current snapshot supplies evidence for admission; checking does not
/// invalidate an already verified selection.
struct AnalysisUSBDiscoveryState {
    enum Activity { case idle, checking, waiting, suspended }
    enum Outcome { case pending, current, failed(USBDiscoveryProblem) }

    var activity: Activity = .idle
    var outcome: Outcome = .pending
    var snapshot: USBDiscoverySnapshot?
    var admissionRequest: USBAdmissionRequest?

    var hasCurrentSnapshot: Bool {
        if case .current = outcome { return true }
        return false
    }

    var failure: USBDiscoveryProblem? {
        if case .failed(let problem) = outcome { return problem }
        return nil
    }
}

enum USBTargetReadiness: Equatable {
    case noSelection
    case awaitingRequirement
    case unverified(USBDiscoveryProblem)
    case insufficient(required: Int64, actual: Int64)
    case ready(required: Int64, actual: Int64)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var problem: USBDiscoveryProblem? {
        if case .unverified(let problem) = self { return problem }
        return nil
    }
}
