import Foundation
import SwiftUI

extension AnalysisLogic {
    /// Final read-only identity/capacity check at the analysis handoff boundary.
    /// It uses no subprocess and adds no normal-flow prompt or visible control.
    /// A current registry identity is required in addition to the presentation
    /// cache, including when another child is holding the discovery runner slot.
    func confirmUSBTargetForHandoff(_ proceed: @escaping () -> Void) {
        guard usbDiscoveryState.admissionRequest == nil else { return }
        checkCapacity()
        guard let drive = selectedDriveForInstallation,
              let selected = selectedDrive,
              let expectedIdentity = selectedTargetIdentity,
              let required = usbTargetCapacityRequirement?.minimumBytes else { return }
        let request = UUID()
        let generation = physicalDriveRefreshGeneration
        usbDiscoveryState.admissionRequest = USBAdmissionRequest(id: request)
        log("USB handoff verification started: generation=\(generation), request=\(request), device=\(selected.device), identity=\(expectedIdentity), required=\(required) B.", category: "USBSelection")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let whole = USBDriveLogic.wholeDiskName(from: drive.device)
            let parent = USBDiscoveryRegistryProbe.media(named: whole)
            let expectedParent = expectedIdentity.components(separatedBy: ":").first
            let readiness: USBTargetReadiness
            if parent.map({ String($0.identity) }) != expectedParent {
                readiness = .unverified(parent == nil ? .identityUnavailable : .identityChanged)
            } else if selected.isWholeDiskTarget {
                if let actual = parent?.capacityBytes {
                    readiness = actual >= required ? .ready(required: required, actual: actual) : .insufficient(required: required, actual: actual)
                } else { readiness = .unverified(.capacityUnavailable) }
            } else {
                let media = USBDiscoveryRegistryProbe.media(named: selected.device, whole: false)
                let identity = media.flatMap { media in expectedParent.map { "\($0):\(media.identity)" } }
                if identity != expectedIdentity || USBDriveLogic.getBSDName(from: selected.url) != selected.device {
                    readiness = .unverified(.identityUnavailable)
                } else if USBDriveLogic.detectPartitionScheme(forBSDName: whole) != .gpt || USBDriveLogic.detectFileSystemFormat(forVolumeURL: selected.url) != .hfsPlus {
                    readiness = .unverified(.incompleteData)
                } else if let values = try? selected.url.resourceValues(forKeys: [.volumeTotalCapacityKey]), let actual = values.volumeTotalCapacity, actual > 0 {
                    let actual = Int64(actual)
                    readiness = actual >= required ? .ready(required: required, actual: actual) : .insufficient(required: required, actual: actual)
                } else { readiness = .unverified(.capacityUnavailable) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let pending = self.usbDiscoveryState.admissionRequest, pending.id == request else {
                    self.log("USB handoff verification discarded: request=\(request), reason=lifecycle cancellation.", category: "USBSelection")
                    return
                }
                self.usbDiscoveryState.admissionRequest = nil
                guard !pending.isCancelled else {
                    self.log("USB handoff verification discarded: request=\(request), reason=lifecycle cancellation.", category: "USBSelection")
                    return
                }
                guard self.isDriveRefreshVisible, NSApp.isActive,
                      self.selectedDrive?.selectionID == selected.selectionID,
                      self.selectedTargetIdentity == expectedIdentity,
                      self.usbTargetCapacityRequirement?.minimumBytes == required else {
                    self.log("USB handoff verification discarded: request=\(request), reason=selection, source or lifecycle changed.", category: "USBSelection")
                    return
                }
                self.checkCapacity()
                // A whole-enumeration failure received during the check still
                // invalidates the old snapshot. Never overwrite that block.
                guard self.usbTargetReadiness.isReady else {
                    self.log("USB handoff blocked: request=\(request), current readiness=\(self.usbTargetReadiness).", category: "USBSelection")
                    return
                }
                let previous = self.usbTargetReadiness
                withAnimation(.easeInOut(duration: 0.24)) {
                    // Keep the evidence and readiness consistent. In particular,
                    // reselecting a target must not restore a failed handoff from
                    // the scan's older capacity/identity evidence.
                    if let snapshot = self.usbDiscoveryState.snapshot {
                        var verification = snapshot.verification
                        let capacity: Result<Int64, USBDiscoveryProblem>
                        switch readiness {
                        case .ready(_, let actual), .insufficient(_, let actual): capacity = .success(actual)
                        case .unverified(let problem): capacity = .failure(problem)
                        default: capacity = .failure(.incompleteData)
                        }
                        verification[selected.selectionID] = USBTargetVerification(identity: expectedIdentity, capacity: capacity)
                        var issues = snapshot.issues.filter { $0.device != selected.device }
                        if let problem = readiness.problem { issues.append(USBDiscoveryIssue(device: selected.device, problem: problem)) }
                        self.usbDiscoveryState.snapshot = USBDiscoverySnapshot(
                            physicalDrives: snapshot.physicalDrives, optionDrives: snapshot.optionDrives,
                            verification: verification, issues: issues, allowExternalDrives: snapshot.allowExternalDrives
                        )
                    }
                    self.usbTargetReadiness = readiness
                }
                self.log("USB handoff verification completed: request=\(request), device=\(selected.device), previous=\(previous), result=\(readiness).", category: "USBSelection")
                if readiness.isReady { proceed() }
            }
        }
    }
}
