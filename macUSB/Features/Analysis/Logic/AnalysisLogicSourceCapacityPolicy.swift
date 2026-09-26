import Foundation

struct USBTargetCapacityRequirement {
    let displayCapacityGB: Int
    let minimumBytes: Int64
    let sourceSizeBytes: Int64?
    let usedFallback: Bool

    static func forSource(at sourceURL: URL) throws -> USBTargetCapacityRequirement {
        let sourceBytes = try sourceSizeBytes(at: sourceURL)
        guard sourceBytes > 0 else { throw SourceSizeError.invalidSize }

        let wholeHundreds = sourceBytes / 100
        let remainder = sourceBytes % 100
        let (scaledHundreds, overflow) = wholeHundreds.multipliedReportingOverflow(by: 105)
        guard !overflow else { throw SourceSizeError.overflow }
        let marginRemainder = (remainder * 105 + 99) / 100
        let (minimumBytes, sumOverflow) = scaledHundreds.addingReportingOverflow(marginRemainder)
        guard !sumOverflow else { throw SourceSizeError.overflow }

        var displayGB = 2
        while minimumBytes > Int64(displayGB) * 1_000_000_000 {
            let (next, classOverflow) = displayGB.multipliedReportingOverflow(by: 2)
            guard !classOverflow, next <= Int64.max / 1_000_000_000 else {
                throw SourceSizeError.overflow
            }
            displayGB = next
        }

        return USBTargetCapacityRequirement(
            displayCapacityGB: displayGB,
            minimumBytes: minimumBytes,
            sourceSizeBytes: sourceBytes,
            usedFallback: false
        )
    }

    static func fallback(macOSMajorVersion: Int? = nil) -> USBTargetCapacityRequirement {
        let isModernMacOS = (macOSMajorVersion ?? 0) >= 15
        return USBTargetCapacityRequirement(
            displayCapacityGB: isModernMacOS ? 32 : 16,
            minimumBytes: isModernMacOS ? 28_000_000_000 : 15_000_000_000,
            sourceSizeBytes: nil,
            usedFallback: true
        )
    }

    private static func sourceSizeBytes(at sourceURL: URL) throws -> Int64 {
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw SourceSizeError.invalidSize }
        if values.isDirectory == true {
            guard sourceURL.pathExtension.lowercased() == "app" else {
                throw SourceSizeError.invalidSize
            }
            return try appBundleSizeBytes(at: sourceURL)
        }
        return try regularFileSizeBytes(at: sourceURL)
    }

    private static func appBundleSizeBytes(at appURL: URL) throws -> Int64 {
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else { throw SourceSizeError.invalidSize }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            let size = try regularFileSizeBytes(at: fileURL)
            let (sum, overflow) = total.addingReportingOverflow(size)
            guard !overflow else { throw SourceSizeError.overflow }
            total = sum
        }
        if let traversalError { throw traversalError }
        return total
    }

    private static func regularFileSizeBytes(at fileURL: URL) throws -> Int64 {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw SourceSizeError.invalidSize }
        if let size = values.fileSize, size >= 0 { return Int64(size) }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value >= 0 else {
            throw SourceSizeError.invalidSize
        }
        return size.int64Value
    }

    private enum SourceSizeError: Error {
        case invalidSize
        case overflow
    }
}

extension AnalysisLogic {
    func applySourceCapacityRequirement(
        _ resolvedRequirement: USBTargetCapacityRequirement?,
        sourceURL: URL,
        macOSMajorVersion: Int? = nil
    ) {
        let requirement = resolvedRequirement
            ?? USBTargetCapacityRequirement.fallback(macOSMajorVersion: macOSMajorVersion)
        usbTargetCapacityRequirement = requirement
        shouldShowSourceSizeUnavailableAlert = requirement.usedFallback

        if let sourceBytes = requirement.sourceSizeBytes {
            log("Source capacity: path=\(sourceURL.path), bytes=\(sourceBytes), margin=5%, minimum=\(requirement.minimumBytes), class=\(requirement.displayCapacityGB) GB")
        } else {
            logError("Source size unavailable: path=\(sourceURL.path), fallback minimum=\(requirement.minimumBytes), class=\(requirement.displayCapacityGB) GB")
        }
        if selectedDrive != nil { checkCapacity() }
    }
}
