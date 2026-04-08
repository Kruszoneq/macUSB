import Foundation

extension MontereyDownloadFlowModel {
    func uniqueCollisionSafeURL(
        in directoryURL: URL,
        preferredFileName: String
    ) -> URL {
        let preferredURL = directoryURL.appendingPathComponent(preferredFileName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let nsName = preferredFileName as NSString
        let baseName = nsName.deletingPathExtension
        let ext = nsName.pathExtension

        var index = 2
        while true {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(baseName) (\(index))"
            } else {
                candidateName = "\(baseName) (\(index)).\(ext)"
            }
            let candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: true)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }
}
