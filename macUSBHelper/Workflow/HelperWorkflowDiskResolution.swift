import Foundation

extension HelperWorkflowExecutor {
    func resolvePartitionTargetWholeDisk(
        fromRequestedBSDName requestedBSDName: String,
        targetVolumePath: String,
        fallbackWholeDisk: String
    ) -> String {
        let requestedWhole = (try? extractWholeDiskName(from: requestedBSDName)) ?? fallbackWholeDisk
        var containerReferences: [String] = []
        let candidateArguments: [[String]] = [
            ["info", "-plist", targetVolumePath],
            ["info", "-plist", "/dev/\(requestedBSDName)"],
            ["info", "-plist", "/dev/\(requestedWhole)"],
            ["list", "-plist", "/dev/\(requestedWhole)"]
        ]

        for arguments in candidateArguments {
            guard let plist = runDiskutilPlistCommand(arguments: arguments) else { continue }
            containerReferences.append(contentsOf: extractAPFSContainerReferences(from: plist))
            if let physicalWhole = extractAPFSPhysicalStoreWholeDisk(from: plist) {
                return physicalWhole
            }
            if let parentWhole = extractParentWholeDisk(from: plist),
               parentWhole != requestedWhole {
                return parentWhole
            }
        }

        let uniqueContainerReferences = Array(Set(containerReferences))
        for containerRef in uniqueContainerReferences {
            let normalizedContainerRef = (try? extractWholeDiskName(from: containerRef)) ?? requestedWhole
            let apfsCandidates: [[String]] = [
                ["apfs", "list", "-plist", "/dev/\(normalizedContainerRef)"],
                ["info", "-plist", "/dev/\(normalizedContainerRef)"]
            ]

            for arguments in apfsCandidates {
                guard let plist = runDiskutilPlistCommand(arguments: arguments) else { continue }
                if let physicalWhole = extractAPFSPhysicalStoreWholeDisk(from: plist) {
                    return physicalWhole
                }
                if let parentWhole = extractParentWholeDisk(from: plist),
                   parentWhole != requestedWhole {
                    return parentWhole
                }
            }
        }

        return fallbackWholeDisk
    }
    func runDiskutilPlistCommand(arguments: [String]) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }
    func extractParentWholeDisk(from plist: [String: Any]) -> String? {
        if let parent = plist["ParentWholeDisk"] as? String,
           let normalized = try? extractWholeDiskName(from: parent) {
            return normalized
        }

        for value in plist.values {
            if let childPlist = value as? [String: Any],
               let found = extractParentWholeDisk(from: childPlist) {
                return found
            }

            if let childArray = value as? [[String: Any]] {
                for child in childArray {
                    if let found = extractParentWholeDisk(from: child) {
                        return found
                    }
                }
            }
        }

        return nil
    }
    func extractAPFSPhysicalStoreWholeDisk(from plist: [String: Any]) -> String? {
        if let stores = plist["APFSPhysicalStores"] as? [[String: Any]] {
            for store in stores {
                if let identifier = store["DeviceIdentifier"] as? String,
                   let whole = try? extractWholeDiskName(from: identifier) {
                    return whole
                }
            }
        }

        if let stores = plist["APFSPhysicalStores"] as? [String] {
            for identifier in stores {
                if let whole = try? extractWholeDiskName(from: identifier) {
                    return whole
                }
            }
        }

        for value in plist.values {
            if let childPlist = value as? [String: Any],
               let found = extractAPFSPhysicalStoreWholeDisk(from: childPlist) {
                return found
            }

            if let childArray = value as? [[String: Any]] {
                for child in childArray {
                    if let found = extractAPFSPhysicalStoreWholeDisk(from: child) {
                        return found
                    }
                }
            }
        }

        return nil
    }
    func extractAPFSContainerReferences(from plist: [String: Any]) -> [String] {
        var result: [String] = []

        if let containerRef = plist["APFSContainerReference"] as? String {
            result.append(containerRef)
        }

        if let containerRefs = plist["APFSContainerReference"] as? [String] {
            result.append(contentsOf: containerRefs)
        }

        for value in plist.values {
            if let childPlist = value as? [String: Any] {
                result.append(contentsOf: extractAPFSContainerReferences(from: childPlist))
            } else if let childArray = value as? [[String: Any]] {
                for child in childArray {
                    result.append(contentsOf: extractAPFSContainerReferences(from: child))
                }
            }
        }

        return result
    }
    func extractWholeDiskName(from bsdName: String) throws -> String {
        guard let range = bsdName.range(of: #"^disk[0-9]+"#, options: .regularExpression) else {
            throw HelperExecutionError.invalidRequest("Nieprawidłowy identyfikator nośnika: \(bsdName)")
        }
        return String(bsdName[range])
    }
    func resolvePPCSourceArgument(from sourcePath: String) -> String {
        guard sourcePath.hasPrefix("/Volumes/") else {
            return sourcePath
        }

        guard let devicePath = resolveDevicePathForMountedVolume(sourcePath) else {
            return sourcePath
        }

        return devicePath
    }
    func resolveDevicePathForMountedVolume(_ volumePath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", volumePath]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let deviceIdentifier = plist["DeviceIdentifier"] as? String,
              deviceIdentifier.hasPrefix("disk") else {
            return nil
        }

        return "/dev/\(deviceIdentifier)"
    }
}
