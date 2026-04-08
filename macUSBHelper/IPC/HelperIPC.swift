import Foundation

enum HelperWorkflowKind: String, Codable {
    case standard
    case legacyRestore
    case mavericks
    case ppc
}

struct HelperWorkflowRequestPayload: Codable {
    let workflowKind: HelperWorkflowKind
    let systemName: String
    let sourceAppPath: String
    let originalImagePath: String?
    let tempWorkPath: String
    let targetVolumePath: String
    let targetBSDName: String
    let targetLabel: String
    let needsPreformat: Bool
    let isCatalina: Bool
    let isSierra: Bool
    let needsCodesign: Bool
    let requiresApplicationPathArg: Bool
    let requesterUID: Int?
}

struct HelperProgressEventPayload: Codable {
    let workflowID: String
    let stageKey: String
    let stageTitleKey: String
    let percent: Double
    let statusKey: String
    let logLine: String?
    let timestamp: Date
}

struct HelperWorkflowResultPayload: Codable {
    let workflowID: String
    let success: Bool
    let failedStage: String?
    let errorCode: Int?
    let errorMessage: String?
    let isUserCancelled: Bool
}

struct DownloaderAssemblyRequestPayload: Codable {
    let packagePath: String
    let outputDirectoryPath: String
    let expectedAppName: String
    let finalDestinationDirectoryPath: String
    let cleanupSessionFiles: Bool
    let requesterUID: UInt32
    let patchLegacyDistributionInDebug: Bool
}

struct DownloaderAssemblyProgressPayload: Codable {
    let workflowID: String
    let percent: Double
    let statusText: String
    let logLine: String?
}

struct DownloaderAssemblyResultPayload: Codable {
    let workflowID: String
    let success: Bool
    let outputAppPath: String?
    let errorMessage: String?
    let cleanupRequested: Bool
    let cleanupSucceeded: Bool
    let cleanupErrorMessage: String?
}

struct DownloaderCleanupRequestPayload: Codable {
    let sessionRootPath: String
}

struct DownloaderCleanupResultPayload: Codable {
    let success: Bool
    let errorMessage: String?
}

@objc(MacUSBPrivilegedHelperToolXPCProtocol)
protocol PrivilegedHelperToolXPCProtocol {
    func startWorkflow(_ requestData: NSData, reply: @escaping (NSString?, NSError?) -> Void)
    func cancelWorkflow(_ workflowID: String, reply: @escaping (Bool, NSError?) -> Void)
    func startDownloaderAssembly(_ requestData: NSData, reply: @escaping (NSString?, NSError?) -> Void)
    func cancelDownloaderAssembly(_ workflowID: String, reply: @escaping (Bool, NSError?) -> Void)
    func cleanupDownloaderSession(_ requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void)
    func queryHealth(_ reply: @escaping (Bool, NSString) -> Void)
}

@objc(MacUSBPrivilegedHelperClientXPCProtocol)
protocol PrivilegedHelperClientXPCProtocol {
    func receiveProgressEvent(_ eventData: NSData)
    func finishWorkflow(_ resultData: NSData)
    func receiveDownloaderAssemblyProgress(_ eventData: NSData)
    func finishDownloaderAssembly(_ resultData: NSData)
}

enum HelperXPCCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
