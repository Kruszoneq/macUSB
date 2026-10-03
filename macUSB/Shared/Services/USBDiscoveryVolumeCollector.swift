import Foundation

/// Prepares Option rows from current physical evidence. Resource-value failures
/// remain explicit instead of turning a mounted target's capacity into zero.
enum USBDiscoveryVolumeCollector {
    struct Collection {
        var drives: [USBDrive] = []
        var verification: [String: USBTargetVerification] = [:]
        var issues: [USBDiscoveryIssue] = []
    }

    static func collect(
        physical: [USBDrive], verification: [String: USBTargetVerification],
        allowExternalDrives: Bool, cancellation: USBDiscoveryCancellation,
        record: (String, String, String) -> Void,
        recover: (String, String) -> Void
    ) -> Collection {
        var result = Collection()
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeTotalCapacityKey, .volumeUUIDStringKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: .skipHiddenVolumes) else {
            result.issues.append(USBDiscoveryIssue(device: "mounted volumes", problem: .incompleteData))
            record("Mounted-volume enumeration returned no metadata; physical targets remain independently verified.", "volumes", "incompleteData")
            return result
        }
        recover("Mounted-volume enumeration recovered.", "volumes")
        for url in urls {
            if cancellation.isCancelled { return result }
            let device = USBDriveLogic.getBSDName(from: url)
            guard let parent = physical.first(where: { $0.device == USBDriveLogic.wholeDiskName(from: device) }),
                  let parentProof = verification[parent.selectionID], parentProof.problem == nil else { continue }
            if USBDriveLogic.isNetworkVolume(url: url) { continue }
            guard parent.partitionScheme == .gpt,
                  USBDriveLogic.detectFileSystemFormat(forVolumeURL: url) == .hfsPlus else {
                record("Volume \(device) omitted: Option requires GPT/HFS+.", "qualification.\(device)", "optionFormat")
                continue
            }
            let values: URLResourceValues?
            var problem: USBDiscoveryProblem?
            do { values = try url.resourceValues(forKeys: keys) }
            catch {
                values = nil
                problem = .incompleteData
                record("Volume \(device) metadata read failed: \(error).", "metadata.\(device)", "incompleteData")
            }
            if values?.volumeIsInternal == true { continue }
            if !allowExternalDrives, values?.volumeIsRemovable == false {
                record("Volume \(device) omitted: non-removable volume; AllowExternalDrives=false.", "qualification.\(device)", "externalPolicy")
                continue
            }
            if values?.volumeIsInternal == nil || (!allowExternalDrives && values?.volumeIsRemovable == nil) || values?.volumeName == nil {
                problem = .incompleteData
            }
            let capacity = values?.volumeTotalCapacity.flatMap { $0 > 0 ? Int64($0) : nil }
            if capacity == nil, problem == nil { problem = .capacityUnavailable }
            let media = USBDiscoveryRegistryProbe.media(named: device, whole: false)
            let identity = media.flatMap { media in parentProof.identity.map { "\($0):\(media.identity)" } }
            if identity == nil { problem = .identityUnavailable }
            let drive = USBDrive(
                name: values?.volumeName ?? url.lastPathComponent, device: device,
                size: capacity.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--",
                url: url, usbSpeed: parent.usbSpeed, partitionScheme: .gpt, fileSystemFormat: .hfsPlus
            )
            let proof = USBTargetVerification(identity: identity, capacity: problem.map { .failure($0) } ?? capacity.map { .success($0) } ?? .failure(.capacityUnavailable), confirmedAt: problem == nil ? ProcessInfo.processInfo.systemUptime : nil)
            if problem == nil { recover("Volume \(device) metadata recovered.", "metadata.\(device)") }
            result.drives.append(drive)
            result.verification[drive.selectionID] = proof
            if let problem { result.issues.append(USBDiscoveryIssue(device: device, problem: problem)) }
            record("Volume \(device) qualification=\(problem == nil ? "verified" : "unavailable"), capacity=\(capacity.map(String.init) ?? "unknown") B, identity=\(identity ?? "unknown"), reason=\(problem.map { String(describing: $0) } ?? "none").", "qualification.\(device)", "\(proof.identity ?? "unknown"):\(proof.capacity)")
        }
        result.drives.sort { $0.device.localizedStandardCompare($1.device) == .orderedAscending }
        return result
    }
}
