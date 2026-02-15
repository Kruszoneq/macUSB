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

    init(
        workflowID: String,
        stageKey: String,
        stageTitleKey: String,
        percent: Double,
        statusKey: String,
        logLine: String?,
        timestamp: Date
    ) {
        self.workflowID = workflowID
        self.stageKey = stageKey
        self.stageTitleKey = stageTitleKey
        self.percent = percent
        self.statusKey = statusKey
        self.logLine = logLine
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case workflowID
        case stageKey
        case stageTitleKey
        case stageTitle
        case percent
        case statusKey
        case statusText
        case logLine
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        workflowID = try container.decode(String.self, forKey: .workflowID)
        stageKey = try container.decode(String.self, forKey: .stageKey)
        percent = try container.decode(Double.self, forKey: .percent)
        logLine = try container.decodeIfPresent(String.self, forKey: .logLine)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        stageTitleKey =
            try container.decodeIfPresent(String.self, forKey: .stageTitleKey) ??
            container.decode(String.self, forKey: .stageTitle)

        statusKey =
            try container.decodeIfPresent(String.self, forKey: .statusKey) ??
            container.decode(String.self, forKey: .statusText)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workflowID, forKey: .workflowID)
        try container.encode(stageKey, forKey: .stageKey)
        try container.encode(stageTitleKey, forKey: .stageTitleKey)
        try container.encode(percent, forKey: .percent)
        try container.encode(statusKey, forKey: .statusKey)
        try container.encodeIfPresent(logLine, forKey: .logLine)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

struct HelperWorkflowResultPayload: Codable {
    let workflowID: String
    let success: Bool
    let failedStage: String?
    let errorCode: Int?
    let errorMessage: String?
    let isUserCancelled: Bool
}

@objc(MacUSBPrivilegedHelperToolXPCProtocol)
protocol PrivilegedHelperToolXPCProtocol {
    func startWorkflow(_ requestData: NSData, reply: @escaping (NSString?, NSError?) -> Void)
    func cancelWorkflow(_ workflowID: String, reply: @escaping (Bool, NSError?) -> Void)
    func queryHealth(_ reply: @escaping (Bool, NSString) -> Void)
}

@objc(MacUSBPrivilegedHelperClientXPCProtocol)
protocol PrivilegedHelperClientXPCProtocol {
    func receiveProgressEvent(_ eventData: NSData)
    func finishWorkflow(_ resultData: NSData)
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
