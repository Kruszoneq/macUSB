import Foundation

/// Analysis-only discovery. Legacy USBDriveLogic entry points retain their
/// existing contracts for callers in other stages of the application.
enum USBTargetDiscoveryService {
    static func scan(
        allowExternalDrives: Bool, cancellation: USBDiscoveryCancellation,
        scanID: UInt, workflow: AppLogging.Workflow?, diagnostics: USBDiscoveryDiagnostics, manualRetry: Bool = false
    ) -> USBDiscoveryResult {
        func record(_ text: String, key: String, signature: String) {
            diagnostics.record("Scan \(scanID): \(text)", key: key, signature: signature, workflow: workflow, force: manualRetry)
        }
        func query(_ arguments: [String], device: String) -> Result<[String: Any], USBDiscoveryProblem> {
            let command = "/usr/sbin/diskutil " + arguments.joined(separator: " ")
            let report = USBDiscoveryProcessRunner.shared.runReport(
                arguments: arguments, cancellation: cancellation,
                diagnostic: { message in
                    if message == "Discovery subprocess slot released after observed child exit." {
                        diagnostics.recover("Scan \(scanID): \(message)", key: "process.\(device).retained", workflow: workflow)
                    } else {
                        let signature = message.replacingOccurrences(of: #"pid=\d+"#, with: "pid=<child>", options: .regularExpression)
                        let key = message.contains("retaining subprocess slot") ? "process.\(device).retained" : "process.\(device).\(signature)"
                        record(message, key: key, signature: signature)
                    }
                }
            )
            let status = report.exitStatus.map(String.init) ?? "unavailable"
            let duration = String(format: "%.3f", report.duration)
            switch report.result {
            case .failure(let failure):
                record(
                    "Query device=\(device), command=\(command), duration=\(duration)s, category=\(failure), exit=\(status), detail=\(report.detail ?? "none").\nstdout (bounded): \(snippet(report.stdout))\nstderr (bounded): \(snippet(report.stderr))",
                    key: "query.\(device)", signature: "\(failure):\(report.detail ?? ""):\(snippet(report.stdout)):\(snippet(report.stderr))"
                )
                return .failure(.query(failure))
            case .success(let data):
                do {
                    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                        throw USBDiscoveryProblem.malformedData
                    }
                    if manualRetry {
                        record("Query device=\(device), command=\(command), duration=\(duration)s, result=success, exit=\(status), stdout=\(data.count) bytes, stderr (bounded): \(snippet(report.stderr)).", key: "query.\(device)", signature: "recovered")
                    }
                    diagnostics.recover("Scan \(scanID): Query recovered: device=\(device), command=\(command), result=success, exit=\(status).", key: "query.\(device)", workflow: workflow)
                    return .success(plist)
                } catch {
                    record("Query device=\(device), command=\(command), duration=\(duration)s, exit=\(status), category=malformedData, parsing=\(error).\nstdout (bounded): \(snippet(data))\nstderr (bounded): \(snippet(report.stderr))", key: "query.\(device)", signature: "malformedData:\(error):\(snippet(data))")
                    return .failure(.malformedData)
                }
            }
        }

        let externalList: [String: Any]
        switch query(["list", "-plist", "external"], device: "external") {
        case .success(let plist): externalList = plist
        case .failure(.query(.busy)): return .busy
        case .failure(.query(.cancelled)): return .cancelled
        case .failure(let problem): return .failed(problem)
        }
        guard let wholeDisks = externalList["WholeDisks"] as? [String],
              Set(wholeDisks).count == wholeDisks.count,
              wholeDisks.allSatisfy({ $0.range(of: #"^disk\d+$"#, options: .regularExpression) != nil }) else {
            record("Enumeration missing or invalid WholeDisks array. Keys=\(externalList.keys.sorted()).", key: "enumeration", signature: "incompleteData")
            return .failed(.incompleteData)
        }

        diagnostics.recover("Scan \(scanID): Whole-disk enumeration recovered.", key: "enumeration", workflow: workflow)

        var drives: [USBDrive] = []
        var verification: [String: USBTargetVerification] = [:]
        var issues: [USBDiscoveryIssue] = []
        for device in wholeDisks {
            if cancellation.isCancelled { return .cancelled }
            let before = USBDiscoveryRegistryProbe.media(named: device)
            let info: [String: Any]?
            var problem: USBDiscoveryProblem?
            switch query(["info", "-plist", "/dev/\(device)"], device: device) {
            case .success(let value): info = value
            case .failure(.query(.cancelled)): return .cancelled
            case .failure(let failure): info = nil; problem = failure
            }
            let after = USBDiscoveryRegistryProbe.media(named: device)
            let confirmedAt = ProcessInfo.processInfo.systemUptime
            let sameMedia = before?.identity != nil && before?.identity == after?.identity
            let registryUSB = sameMedia && after?.isExternalPhysicalUSB == true
            // diskutil info names this field WholeDisk; IOMedia uses Whole.
            // Bind all info-derived metadata to the same validated device.
            let matchingInfo = info.flatMap { $0["DeviceIdentifier"] as? String == device && $0["WholeDisk"] as? Bool == true ? $0 : nil }

            if let info {
                let matchesRequestedDevice = matchingInfo != nil
                // Explicit exclusions are ordinary filtering, not discovery failures.
                let internalMedia = (info["Internal"] as? Bool) ?? (info["OSInternalMedia"] as? Bool)
                if matchesRequestedDevice, let bus = info["BusProtocol"] as? String, bus.uppercased() != "USB" {
                    record("Device \(device) omitted: transport=\(bus).", key: "qualification.\(device)", signature: "nonUSB"); continue
                }
                if matchesRequestedDevice, internalMedia == true || (info["VirtualOrPhysical"] as? String)?.lowercased() == "virtual" {
                    record("Device \(device) omitted: internal or virtual media.", key: "qualification.\(device)", signature: "internalOrVirtual"); continue
                }
                if matchesRequestedDevice, info["RemovableMediaOrExternalDevice"] as? Bool == false {
                    record("Device \(device) omitted: not removable or external.", key: "qualification.\(device)", signature: "notExternal"); continue
                }
                let confirmedByInfo = (info["BusProtocol"] as? String)?.uppercased() == "USB"
                    && internalMedia == false
                    && (info["VirtualOrPhysical"] as? String)?.lowercased() == "physical"
                    && matchesRequestedDevice
                if (!confirmedByInfo && !registryUSB) || !matchesRequestedDevice || info["Error"] != nil {
                    problem = .incompleteData
                    let reportedDevice = info["DeviceIdentifier"] as? String ?? "missing or invalid"
                    let wholeDisk = (info["WholeDisk"] as? Bool).map(String.init) ?? "missing or invalid"
                    record("Device \(device) has incomplete type/identity data: DeviceIdentifier=\(reportedDevice), WholeDisk=\(wholeDisk), infoUSB=\(confirmedByInfo), registryUSB=\(registryUSB), errorPresent=\(info["Error"] != nil). Keys=\(info.keys.sorted()).", key: "metadata.\(device)", signature: "incompleteData:\(reportedDevice):\(wholeDisk):\(confirmedByInfo):\(registryUSB)")
                }
                guard confirmedByInfo || registryUSB else {
                    issues.append(USBDiscoveryIssue(device: device, problem: problem ?? .incompleteData))
                    record("Device \(device) omitted: physical external USB type could not be confirmed.", key: "qualification.\(device)", signature: "unconfirmedUSB"); continue
                }
            } else if !registryUSB {
                issues.append(USBDiscoveryIssue(device: device, problem: problem ?? .incompleteData))
                record("Device \(device) omitted after query failure: registry does not confirm current physical external USB media.", key: "qualification.\(device)", signature: "unconfirmedUSB"); continue
            }

            let removable = (matchingInfo?["RemovableMedia"] as? Bool) ?? (matchingInfo?["Removable"] as? Bool) ?? after?.removable
            if !allowExternalDrives, removable == false {
                if let problem { issues.append(USBDiscoveryIssue(device: device, problem: problem)) }
                record("Device \(device) omitted: non-removable media; AllowExternalDrives=false.", key: "qualification.\(device)", signature: "externalPolicy"); continue
            }
            if !allowExternalDrives, removable == nil {
                problem = problem ?? .incompleteData
                record("Device \(device) blocked: removable-media policy could not be confirmed.", key: "metadata.\(device)", signature: "removablePolicyUnknown")
            }
            if !sameMedia { problem = .identityUnavailable }
            let capacity = matchingInfo.flatMap { positiveCapacity($0["TotalSize"]) }
            if capacity == nil, problem == nil { problem = .capacityUnavailable }
            let drive = USBDrive(
                name: matchingInfo?["MediaName"] as? String ?? device, device: device,
                size: capacity.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--",
                url: URL(fileURLWithPath: "/dev/\(device)"),
                usbSpeed: USBDriveLogic.detectUSBSpeed(forBSDName: device),
                partitionScheme: USBDriveLogic.detectPartitionScheme(forBSDName: device)
            )
            if problem == nil {
                diagnostics.recover("Scan \(scanID): Device \(device) metadata recovered.", key: "metadata.\(device)", workflow: workflow)
            }
            drives.append(drive)
            verification[drive.selectionID] = USBTargetVerification(
                identity: sameMedia ? after.map { String($0.identity) } : nil,
                capacity: problem.map { .failure($0) } ?? capacity.map { .success($0) } ?? .failure(.capacityUnavailable),
                confirmedAt: problem == nil ? confirmedAt : nil
            )
            if let problem { issues.append(USBDiscoveryIssue(device: device, problem: problem)) }
            record("Device \(device) qualification=\(problem == nil ? "verified" : "unavailable"), identity=\(after.map { String($0.identity) } ?? "unknown"), capacity=\(capacity.map(String.init) ?? "unknown") B, reason=\(problem.map { String(describing: $0) } ?? "none").", key: "qualification.\(device)", signature: "\(verification[drive.selectionID]!.identity ?? "unknown"):\(verification[drive.selectionID]!.capacity)")
        }
        drives.sort { $0.device.localizedStandardCompare($1.device) == .orderedAscending }
        let physical = drives
        let collected = USBDiscoveryVolumeCollector.collect(
            physical: physical, verification: verification, allowExternalDrives: allowExternalDrives,
            cancellation: cancellation, record: { record($0, key: $1, signature: $2) },
            recover: { diagnostics.recover("Scan \(scanID): " + $0, key: $1, workflow: workflow) }
        )
        let volumes = collected.drives
        verification.merge(collected.verification) { _, new in new }
        issues.append(contentsOf: collected.issues)
        // A disk may have been unplugged/replaced while another disk or mounted
        // volume was being read. Recheck current registry identities before
        // publishing any evidence; do not silently admit a reused BSD name.
        for drive in physical {
            if cancellation.isCancelled { return .cancelled }
            let current = USBDiscoveryRegistryProbe.media(named: drive.device)
            let currentID = current.map { String($0.identity) }
            guard currentID == verification[drive.selectionID]?.identity, currentID != nil else {
                let problem: USBDiscoveryProblem = current == nil ? .identityUnavailable : .identityChanged
                for candidate in [drive] + volumes.filter({ USBDriveLogic.wholeDiskName(from: $0.device) == drive.device }) {
                    verification[candidate.selectionID] = USBTargetVerification(identity: verification[candidate.selectionID]?.identity, capacity: .failure(problem))
                }
                issues.append(USBDiscoveryIssue(device: drive.device, problem: problem))
                record("Device \(drive.device) lost identity verification before publication: current=\(currentID ?? "unknown"), reason=\(problem).", key: "publication.\(drive.device)", signature: "\(problem)")
                continue
            }
        }
        for volume in volumes {
            if cancellation.isCancelled { return .cancelled }
            let parent = physical.first { $0.device == USBDriveLogic.wholeDiskName(from: volume.device) }
            let current = USBDiscoveryRegistryProbe.media(named: volume.device, whole: false)
            let currentID = current.flatMap { media in parent.flatMap { verification[$0.selectionID]?.identity }.map { "\($0):\(media.identity)" } }
            if currentID == nil || currentID != verification[volume.selectionID]?.identity {
                verification[volume.selectionID] = USBTargetVerification(identity: verification[volume.selectionID]?.identity, capacity: .failure(.identityUnavailable))
                issues.append(USBDiscoveryIssue(device: volume.device, problem: .identityUnavailable))
                record("Volume \(volume.device) lost identity verification before publication.", key: "publication.\(volume.device)", signature: "identityUnavailable")
            }
        }
        for drive in physical + volumes where verification[drive.selectionID]?.problem == nil {
            diagnostics.recover("Scan \(scanID): Device \(drive.device) publication verification recovered.", key: "publication.\(drive.device)", workflow: workflow)
        }
        let byParent = Dictionary(grouping: volumes) { USBDriveLogic.wholeDiskName(from: $0.device) }
        let option = physical.flatMap { [$0] + (byParent[$0.device] ?? []) }
        guard !cancellation.isCancelled else { return .cancelled }
        let snapshot = USBDiscoverySnapshot(physicalDrives: physical, optionDrives: option, verification: verification, issues: issues, allowExternalDrives: allowExternalDrives)
        return issues.isEmpty ? .complete(snapshot) : .partial(snapshot)
    }

    private static func positiveCapacity(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let bytes = Int64(number.stringValue), bytes > 0 else { return nil }
        return bytes
    }

    private static func snippet(_ data: Data) -> String {
        String(decoding: data.prefix(2048), as: UTF8.self) + (data.count > 2048 ? " [truncated]" : "")
    }
}
