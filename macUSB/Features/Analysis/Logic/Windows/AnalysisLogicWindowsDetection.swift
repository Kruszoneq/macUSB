import Foundation

extension AnalysisLogic {
    func detectWindows(fromMountPath mountPath: String, sourceURL: URL) -> WindowsDetectionResult? {
        guard let metadata = readWindowsMetadata(fromMountPath: mountPath, sourceURL: sourceURL) else {
            return nil
        }
        guard let result = classifyWindowsImage(from: metadata) else {
            self.log("Wykryto sygnały Windows, ale nie udało się jednoznacznie sklasyfikować rodziny: \(sourceURL.lastPathComponent)")
            return nil
        }

        self.log("Windows detection: display=\(result.displayName) family=\(result.family.rawValue) supported=\(result.isSupported ? "TAK" : "NIE") arch=\(result.arch.rawValue)")
        self.log("Windows detection evidence: \(result.evidence.joined(separator: ", "))")
        return result
    }
}
