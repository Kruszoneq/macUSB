import Foundation
import CryptoKit
import Darwin

private struct MacUSBootManifest: Decodable {
    struct Container: Decodable {
        let formatVersion: Int
        let headerSize: Int
        let flags: Int
        let size: Int
        let sha256: String
    }
    struct Component: Decodable {
        let offset: Int
        let size: Int
        let sha256: String
    }
    struct StageTwo: Decodable {
        let formatVersion: Int
        let headerSize: Int
        let entryOffset: Int
        let flags: Int
        let offset: Int
        let size: Int
        let sectorCount: Int
        let sha256: String
    }

    let schemaVersion: Int
    let productVersion: String
    let binaryFileName: String
    let checksumFileName: String
    let container: Container
    let mbrPayload: Component
    let stageTwo: StageTwo
}

enum HelperWorkflowWindowsMacUSBootArtifactLoader {
    private static let processPathBufferSize = 4_096
    private static let manifestFileName = "manifest.json"
    private static let pinnedProductVersion = "1.0"
    private static let pinnedBinaryFileName = "macUSBoot-v1.0.bin"
    private static let pinnedChecksumFileName = "macUSBoot-v1.0.bin.sha256"
    private static let pinnedContainerSize = 3_032
    private static let pinnedContainerSHA256 = "729a0852f86a5c7da58dc807f9920159cfc09f97661f0ce4099c80f290253585"
    private static let pinnedMBRPayloadSHA256 = "1eb3bf65781393f8bccbb04c4ad30bb8acc6aed8e3396f150b764e789f816c54"
    private static let pinnedStageTwoSHA256 = "be00204b4c465eb0f09daa7e245cedea741762964e2c9fa20792c19eeb53e11f"

    static func load() throws -> HelperWorkflowWindowsMacUSBootArtifact {
        do {
            return try loadValidatedArtifact()
        } catch let failure as HelperWorkflowWindowsMacUSBootFailure {
            throw failure
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact(
                "resource access failed: \(error.localizedDescription)"
            )
        }
    }

    private static func loadValidatedArtifact() throws -> HelperWorkflowWindowsMacUSBootArtifact {
        let directory = try resourceDirectory()
        try validateDirectory(directory)

        let manifestURL = directory.appendingPathComponent(manifestFileName)

        let manifest: MacUSBootManifest
        do {
            manifest = try JSONDecoder().decode(MacUSBootManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("manifest decode failed: \(error.localizedDescription)")
        }

        try validateManifest(manifest)

        let binaryURL = directory.appendingPathComponent(pinnedBinaryFileName)
        let checksumURL = directory.appendingPathComponent(pinnedChecksumFileName)

        let container = try Data(contentsOf: binaryURL, options: [.mappedIfSafe])
        guard container.count == pinnedContainerSize else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("container size=\(container.count), expected=\(pinnedContainerSize)")
        }
        guard sha256(container) == pinnedContainerSHA256 else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("container SHA-256 mismatch against helper pin")
        }
        try validateChecksumFile(checksumURL)
        try validateContainerHeader(container, manifest: manifest)

        let mbrPayload = container.subdata(
            in: manifest.mbrPayload.offset..<(manifest.mbrPayload.offset + manifest.mbrPayload.size)
        )
        let stageTwo = container.subdata(
            in: manifest.stageTwo.offset..<(manifest.stageTwo.offset + manifest.stageTwo.size)
        )
        guard sha256(mbrPayload) == pinnedMBRPayloadSHA256 else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("MBR payload SHA-256 mismatch against helper pin")
        }
        guard sha256(stageTwo) == pinnedStageTwoSHA256 else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("StageTwo SHA-256 mismatch against helper pin")
        }
        try validateStageTwo(stageTwo, manifest: manifest)

        return HelperWorkflowWindowsMacUSBootArtifact(
            productVersion: pinnedProductVersion,
            binaryFileName: pinnedBinaryFileName,
            completeSize: container.count,
            completeSHA256: pinnedContainerSHA256,
            mbrPayload: mbrPayload,
            stageTwo: stageTwo
        )
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func resourceDirectory() throws -> URL {
        let executableURL = try runningExecutableURL()
        var current = executableURL.deletingLastPathComponent()
        while current.path != "/" {
            if current.lastPathComponent == "Contents",
               current.deletingLastPathComponent().pathExtension == "app" {
                return current.appendingPathComponent("Resources/macUSBoot", isDirectory: true)
            }
            current.deleteLastPathComponent()
        }
        throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact(
            "cannot resolve app resources from executable path: \(executableURL.path)"
        )
    }

    private static func runningExecutableURL() throws -> URL {
        var buffer = [CChar](repeating: 0, count: processPathBufferSize)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(getpid(), pointer.baseAddress, UInt32(pointer.count))
        }
        guard length > 0 else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact(
                "proc_pidpath failed: errno=\(errno), message=\(String(cString: strerror(errno)))"
            )
        }
        let processPath = buffer.withUnsafeBufferPointer { pointer in
            String(cString: pointer.baseAddress!)
        }
        return URL(fileURLWithPath: processPath, isDirectory: false)
            .resolvingSymlinksInPath()
    }

    private static func validateManifest(_ manifest: MacUSBootManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.productVersion == pinnedProductVersion,
              manifest.binaryFileName == pinnedBinaryFileName,
              manifest.checksumFileName == pinnedChecksumFileName,
              manifest.container.formatVersion == 1,
              manifest.container.headerSize == 32,
              manifest.container.flags == 0,
              manifest.container.size == pinnedContainerSize,
              manifest.container.sha256.lowercased() == pinnedContainerSHA256,
              manifest.mbrPayload.offset == 32,
              manifest.mbrPayload.size == 440,
              manifest.mbrPayload.sha256.lowercased() == pinnedMBRPayloadSHA256,
              manifest.stageTwo.formatVersion == 1,
              manifest.stageTwo.headerSize == 16,
              manifest.stageTwo.entryOffset == 16,
              manifest.stageTwo.flags == 0,
              manifest.stageTwo.offset == 472,
              manifest.stageTwo.size == 2560,
              manifest.stageTwo.sectorCount == 5,
              manifest.stageTwo.sha256.lowercased() == pinnedStageTwoSHA256 else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("unsupported or inconsistent manifest")
        }
    }

    private static func validateDirectory(_ directory: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        let expected = Set([manifestFileName, pinnedBinaryFileName, pinnedChecksumFileName])
        guard Set(entries.map(\.lastPathComponent)) == expected else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("resource directory contains missing or additional files")
        }
        for entry in entries {
            try requireRegularFile(entry)
        }
    }

    private static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("non-regular or symbolic file: \(url.lastPathComponent)")
        }
    }

    private static func validateChecksumFile(_ url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text == "\(pinnedContainerSHA256)  \(pinnedBinaryFileName)" else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("checksum file mismatch")
        }
    }

    private static func validateContainerHeader(_ data: Data, manifest: MacUSBootManifest) throws {
        let magic = Array("MUSBPKG".utf8) + [0]
        guard Array(data.prefix(8)) == magic,
              data[8] == UInt8(manifest.container.formatVersion),
              data[9] == UInt8(manifest.container.headerSize),
              uint16(data, 10) == UInt16(manifest.container.flags),
              uint32(data, 12) == UInt32(data.count),
              uint32(data, 16) == UInt32(manifest.mbrPayload.offset),
              uint32(data, 20) == UInt32(manifest.mbrPayload.size),
              uint32(data, 24) == UInt32(manifest.stageTwo.offset),
              uint32(data, 28) == UInt32(manifest.stageTwo.size),
              manifest.mbrPayload.offset + manifest.mbrPayload.size == manifest.stageTwo.offset,
              manifest.stageTwo.offset + manifest.stageTwo.size == data.count else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("container header mismatch")
        }
    }

    private static func validateStageTwo(_ data: Data, manifest: MacUSBootManifest) throws {
        let displacement = Int(data[1])
        guard data[0] == 0xEB,
              displacement > 0,
              displacement < 128,
              Array(data[2..<6]) == Array("MUSB".utf8),
              data[6] == UInt8(manifest.stageTwo.formatVersion),
              data[7] == UInt8(manifest.stageTwo.headerSize),
              uint16(data, 8) == UInt16(manifest.stageTwo.sectorCount),
              uint16(data, 10) == UInt16(manifest.stageTwo.entryOffset),
              uint32(data, 12) == UInt32(manifest.stageTwo.flags),
              2 + displacement == manifest.stageTwo.entryOffset,
              data.count == manifest.stageTwo.sectorCount * 512,
              Array(data.suffix(4)) == Array("MEND".utf8) else {
            throw HelperWorkflowWindowsMacUSBootFailure.invalidArtifact("StageTwo format mismatch")
        }
    }

    private static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
