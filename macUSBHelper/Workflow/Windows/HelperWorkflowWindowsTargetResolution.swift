import Foundation

struct WindowsTargetVolumeResolution {
    let wholeDiskBSDName: String
    let partitionBSDName: String
    let mountPath: String
    let volumeUUID: String
}

private struct WindowsTargetPartitionState {
    let wholeDiskBSDName: String
    let partitionBSDName: String
    let mountPath: String?
    let volumeUUID: String
}

extension HelperWorkflowExecutor {
    func waitForWindowsTargetVolume(
        stage: WorkflowStage,
        wholeDisk: String
    ) throws -> WindowsTargetVolumeResolution {
        var mountAttempts = Set<String>()

        for _ in 0..<70 {
            let candidates = windowsTargetPartitionStates(on: wholeDisk)
            if candidates.count > 1 {
                let partitions = candidates.map(\.partitionBSDName).sorted().joined(separator: ",")
                throw HelperExecutionError.failed(
                    stage: stage.key,
                    exitCode: -1,
                    description: "Wykryto więcej niż jedną partycję FAT32 na docelowym urządzeniu \(wholeDisk): \(partitions)."
                )
            }

            if let target = candidates.first {
                if let mountPath = target.mountPath,
                   isExistingWindowsTargetDirectory(atPath: mountPath) {
                    return WindowsTargetVolumeResolution(
                        wholeDiskBSDName: target.wholeDiskBSDName,
                        partitionBSDName: target.partitionBSDName,
                        mountPath: mountPath,
                        volumeUUID: target.volumeUUID
                    )
                }

                if mountAttempts.insert(target.partitionBSDName).inserted {
                    let exitCode = try runSimpleCommand(
                        executable: "/usr/sbin/diskutil",
                        arguments: ["mount", "/dev/\(target.partitionBSDName)"],
                        stageKey: stage.key,
                        stageTitleKey: stage.titleKey,
                        statusKey: stage.statusKey,
                        failOnNonZeroExit: false
                    )
                    emitProgress(
                        stageKey: stage.key,
                        titleKey: stage.titleKey,
                        percent: latestPercent,
                        statusKey: stage.statusKey,
                        logLine: "Windows target mount requested: disk=\(wholeDisk), partition=\(target.partitionBSDName), exitCode=\(exitCode)",
                        shouldAdvancePercent: false
                    )
                }
            }

            try throwIfCancelled()
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw HelperExecutionError.failed(
            stage: stage.key,
            exitCode: -1,
            description: "Nie znaleziono zamontowanej partycji FAT32 urządzenia docelowego \(wholeDisk) po formatowaniu."
        )
    }

    func requireWindowsPreparedTargetVolumePath(stage: WorkflowStage) throws -> String {
        let wholeDisk = try extractWholeDiskName(from: request.targetBSDName)

        if let currentPath = windowsPreparedTargetVolumePath,
           let target = validatedWindowsTargetVolume(
               atMountPath: currentPath,
               expectedWholeDisk: wholeDisk,
               expectedPartition: windowsPreparedTargetPartitionBSDName,
               expectedVolumeUUID: windowsPreparedTargetVolumeUUID
           ) {
            windowsPreparedTargetPartitionBSDName = target.partitionBSDName
            windowsPreparedTargetVolumePath = target.mountPath
            windowsPreparedTargetVolumeUUID = target.volumeUUID
            return target.mountPath
        }

        let target = try waitForWindowsTargetVolume(stage: stage, wholeDisk: wholeDisk)
        if let expectedPartition = windowsPreparedTargetPartitionBSDName,
           target.partitionBSDName != expectedPartition {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Partycja docelowa Windows zmieniła identyfikator z \(expectedPartition) na \(target.partitionBSDName)."
            )
        }
        if let expectedVolumeUUID = windowsPreparedTargetVolumeUUID,
           target.volumeUUID != expectedVolumeUUID {
            throw HelperExecutionError.failed(
                stage: stage.key,
                exitCode: -1,
                description: "Wolumin docelowy Windows zmienił UUID podczas wykonywania procesu."
            )
        }

        windowsPreparedTargetPartitionBSDName = target.partitionBSDName
        windowsPreparedTargetVolumePath = target.mountPath
        windowsPreparedTargetVolumeUUID = target.volumeUUID

        emitProgress(
            stageKey: stage.key,
            titleKey: stage.titleKey,
            percent: latestPercent,
            statusKey: stage.statusKey,
            logLine: "Windows target path refreshed: disk=\(wholeDisk), partition=\(target.partitionBSDName), mountPath=\(target.mountPath), volumeUUID=\(target.volumeUUID)",
            shouldAdvancePercent: false
        )
        return target.mountPath
    }

    private func windowsTargetPartitionStates(on wholeDisk: String) -> [WindowsTargetPartitionState] {
        guard let list = runDiskutilPlistCommand(arguments: ["list", "-plist", "/dev/\(wholeDisk)"]),
              let disks = list["AllDisksAndPartitions"] as? [[String: Any]],
              let targetDisk = disks.first(where: { ($0["DeviceIdentifier"] as? String) == wholeDisk }),
              let partitions = targetDisk["Partitions"] as? [[String: Any]] else {
            return []
        }

        return partitions.compactMap { partition in
            guard let partitionBSDName = partition["DeviceIdentifier"] as? String,
                  let info = runDiskutilPlistCommand(arguments: ["info", "-plist", "/dev/\(partitionBSDName)"]),
                  let resolvedPartition = info["DeviceIdentifier"] as? String,
                  resolvedPartition == partitionBSDName,
                  let parentWholeDisk = info["ParentWholeDisk"] as? String,
                  parentWholeDisk == wholeDisk,
                  (info["WholeDisk"] as? Bool) == false,
                  isWindowsFATTargetPartition(info) else {
                return nil
            }

            let mountPath = (info["MountPoint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let volumeUUID = (info["VolumeUUID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !volumeUUID.isEmpty else {
                return nil
            }
            return WindowsTargetPartitionState(
                wholeDiskBSDName: parentWholeDisk,
                partitionBSDName: resolvedPartition,
                mountPath: mountPath?.isEmpty == false ? mountPath : nil,
                volumeUUID: volumeUUID
            )
        }
    }

    private func validatedWindowsTargetVolume(
        atMountPath mountPath: String,
        expectedWholeDisk: String,
        expectedPartition: String?,
        expectedVolumeUUID: String?
    ) -> WindowsTargetVolumeResolution? {
        guard isExistingWindowsTargetDirectory(atPath: mountPath),
              let info = runDiskutilPlistCommand(arguments: ["info", "-plist", mountPath]),
              let partitionBSDName = info["DeviceIdentifier"] as? String,
              expectedPartition == nil || partitionBSDName == expectedPartition,
              let parentWholeDisk = info["ParentWholeDisk"] as? String,
              parentWholeDisk == expectedWholeDisk,
              (info["WholeDisk"] as? Bool) == false,
              isWindowsFATTargetPartition(info) else {
            return nil
        }

        let resolvedMountPath = (info["MountPoint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedMountPath,
              !resolvedMountPath.isEmpty,
              resolvedMountPath == mountPath else {
            return nil
        }

        guard let volumeUUID = (info["VolumeUUID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !volumeUUID.isEmpty else {
            return nil
        }
        if let expectedVolumeUUID,
           volumeUUID != expectedVolumeUUID {
            return nil
        }

        return WindowsTargetVolumeResolution(
            wholeDiskBSDName: parentWholeDisk,
            partitionBSDName: partitionBSDName,
            mountPath: resolvedMountPath,
            volumeUUID: volumeUUID
        )
    }

    private func isWindowsFATTargetPartition(_ info: [String: Any]) -> Bool {
        let content = (info["Content"] as? String)?.uppercased()
        let filesystemType = (info["FilesystemType"] as? String)?.lowercased()
        return content == "DOS_FAT_32" && filesystemType == "msdos"
    }

    private func isExistingWindowsTargetDirectory(atPath path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
