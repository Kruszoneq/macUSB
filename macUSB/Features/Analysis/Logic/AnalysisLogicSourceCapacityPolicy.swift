import Foundation

extension AnalysisLogic {
    struct SourceImageCapacityResolution {
        let requiredCapacityGB: Int
        let sourceFileSizeBytes: Int64?
        let sourceFileSizeSource: String?
        let usedFallback: Bool
    }

    private static let sourceCapacityFallbackGB: Int = 16

    func requiredUSBCapacityGBForImageSourceSize(_ fileSizeBytes: Int64) -> Int {
        if fileSizeBytes > 14_000_000_000 {
            return 32
        }
        if fileSizeBytes > 6_000_000_000 {
            return 16
        }
        return 8
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
