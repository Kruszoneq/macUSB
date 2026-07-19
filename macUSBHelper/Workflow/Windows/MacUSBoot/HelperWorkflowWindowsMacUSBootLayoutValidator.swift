import Foundation

enum HelperWorkflowWindowsMacUSBootLayoutValidator {
    static let sectorSize = 512
    static let protectedGapSectorCount = 2047

    static func validate(
        snapshot: HelperWorkflowWindowsMacUSBootDiskSnapshot,
        artifact: HelperWorkflowWindowsMacUSBootArtifact,
        blockSize: UInt32
    ) throws {
        guard blockSize == sectorSize else {
            throw HelperWorkflowWindowsMacUSBootFailure.incompatibleLayout("logical sector size=\(blockSize), expected=512")
        }
        guard snapshot.mbr.count == sectorSize,
              snapshot.gap.count == protectedGapSectorCount * sectorSize else {
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess("incomplete MBR or protected gap read")
        }
        guard snapshot.mbr[510] == 0x55, snapshot.mbr[511] == 0xAA else {
            throw HelperWorkflowWindowsMacUSBootFailure.incompatibleLayout("missing MBR signature 0x55AA")
        }

        let firstEntryOffset = 446
        guard snapshot.mbr[firstEntryOffset] == 0 else {
            throw HelperWorkflowWindowsMacUSBootFailure.incompatibleLayout("first partition is active")
        }
        guard snapshot.mbr[firstEntryOffset + 4] == 0x0B else {
            throw HelperWorkflowWindowsMacUSBootFailure.incompatibleLayout(
                String(format: "first partition type=0x%02X, expected=0x0B", snapshot.mbr[firstEntryOffset + 4])
            )
        }

        let firstLBA = UInt64(uint32(snapshot.mbr, firstEntryOffset + 8))
        let sectorCount = UInt64(uint32(snapshot.mbr, firstEntryOffset + 12))
        guard firstLBA == 2048,
              sectorCount > 0,
              firstLBA <= snapshot.blockCount,
              sectorCount <= snapshot.blockCount - firstLBA else {
            throw HelperWorkflowWindowsMacUSBootFailure.incompatibleLayout(
                "partition extent firstLBA=\(firstLBA), sectors=\(sectorCount), deviceSectors=\(snapshot.blockCount)"
            )
        }

        for entryIndex in 1..<4 {
            let offset = firstEntryOffset + (entryIndex * 16)
            guard snapshot.mbr[offset..<(offset + 16)].allSatisfy({ $0 == 0 }) else {
                throw HelperWorkflowWindowsMacUSBootFailure.incompatibleLayout("partition entry \(entryIndex + 1) is not empty")
            }
        }

        let stageTwoRange = 0..<artifact.stageTwo.count
        let currentStageTwo = snapshot.gap.subdata(in: stageTwoRange)
        guard currentStageTwo.allSatisfy({ $0 == 0 }) || currentStageTwo == artifact.stageTwo else {
            throw HelperWorkflowWindowsMacUSBootFailure.unsafeOccupiedGap("LBA 1-5 contains partial or foreign data")
        }
        guard snapshot.gap.dropFirst(artifact.stageTwo.count).allSatisfy({ $0 == 0 }) else {
            throw HelperWorkflowWindowsMacUSBootFailure.unsafeOccupiedGap("LBA 6-2047 contains nonzero data")
        }
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
