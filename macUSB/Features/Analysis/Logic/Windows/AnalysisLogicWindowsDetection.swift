import Foundation

extension AnalysisLogic {
    func detectWindows(fromMountPath mountPath: String, sourceURL: URL) -> WindowsDetectionResult? {
        guard let metadata = readWindowsMetadata(fromMountPath: mountPath, sourceURL: sourceURL) else {
            return nil
        }
        guard let result = classifyWindowsImage(from: metadata) else {
            self.logWindows("Windows markers detected, but family could not be classified unambiguously: \(sourceURL.lastPathComponent)")
            return nil
        }

        self.logWindows("Windows detection: display=\(result.displayName) family=\(result.family.rawValue) supported=\(result.isSupported ? "yes" : "no") arch=\(result.arch.rawValue)")
        self.logWindows("Windows detection evidence: \(result.evidence.joined(separator: ", "))")
        return result
    }
}
