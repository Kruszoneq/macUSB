import Foundation

extension MontereyDownloadFlowModel {
    func formatTransferStatus(downloadedBytes: Int64, totalBytes: Int64) -> String {
        if totalBytes < 1_000_000_000 {
            let downloadedMB = Double(downloadedBytes) / 1_000_000
            let totalMB = Double(totalBytes) / 1_000_000
            return "\(formatDecimal(downloadedMB, fractionDigits: 1))MB/\(formatDecimal(totalMB, fractionDigits: 1))MB"
        }

        let downloadedGB = Double(downloadedBytes) / 1_000_000_000
        let totalGB = Double(totalBytes) / 1_000_000_000
        return "\(formatDecimal(downloadedGB, fractionDigits: 1))GB/\(formatDecimal(totalGB, fractionDigits: 1))GB"
    }

    func formatDecimal(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
    }
}
