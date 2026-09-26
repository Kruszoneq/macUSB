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
    struct SourceImageCapacityResolution {
        let requiredCapacityGB: Int
        let sourceFileSizeBytes: Int64?
        let sourceFileSizeSource: String?
        let usedFallback: Bool
    }

    private static let sourceCapacityFallbackGB: Int = 16

    func requiredUSBCapacityGBForImageSourceSize(_ fileSizeBytes: Int64) -> Int {
        if fileSizeBytes > 29_400_000_000 {
            return 64
        }
        if fileSizeBytes > 14_700_000_000 {
            return 32
        }
        if fileSizeBytes > 7_300_000_000 {
            return 16
        }
        if fileSizeBytes > 3_600_000_000 {
            return 8
        }
        if fileSizeBytes > 1_800_000_000 {
            return 4
        }
        if fileSizeBytes > 900_000_000 {
            return 2
        }
        return 1
    }

    func resolveImageSourceFileSizeBytes(for sourceURL: URL) -> (bytes: Int64, source: String)? {
        if let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize {
            return (Int64(fileSize), "fileSizeKey")
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let size = attributes[.size] as? NSNumber {
            return (size.int64Value, "attributesOfItem")
        }

        return nil
    }

    func resolveRequiredUSBCapacityForImageSource(_ sourceURL: URL) -> SourceImageCapacityResolution {
        if let fileSizeResolution = resolveImageSourceFileSizeBytes(for: sourceURL) {
            let requiredGB = requiredUSBCapacityGBForImageSourceSize(fileSizeResolution.bytes)
            return SourceImageCapacityResolution(
                requiredCapacityGB: requiredGB,
                sourceFileSizeBytes: fileSizeResolution.bytes,
                sourceFileSizeSource: fileSizeResolution.source,
                usedFallback: false
            )
        }

        return SourceImageCapacityResolution(
            requiredCapacityGB: Self.sourceCapacityFallbackGB,
            sourceFileSizeBytes: nil,
            sourceFileSizeSource: nil,
            usedFallback: true
        )
    }
}
