import Foundation

struct HelperWorkflowWindowsMacUSBootTransaction {
    let device: HelperWorkflowWindowsMacUSBootRawDevice
    let artifact: HelperWorkflowWindowsMacUSBootArtifact
    let confirmUnmounted: () throws -> Void
    let report: (_ statusKey: String, _ logLine: String) -> Void

    func run() throws {
        let snapshot = try readInitialSnapshot()
        report(
            HelperWorkflowLocalizationKeys.windowsInstallMacUSBootCheckingLayout,
            "macUSBoot initial read completed: mbrBytes=512, gapBytes=\(snapshot.gap.count)"
        )
        try HelperWorkflowWindowsMacUSBootLayoutValidator.validate(
            snapshot: snapshot,
            artifact: artifact,
            blockSize: device.blockSize
        )
        report(
            HelperWorkflowLocalizationKeys.windowsInstallMacUSBootCheckingLayout,
            "macUSBoot layout verified: partitionType=0x0B, firstLBA=2048, lba1-5=available_or_identical, lba6-2047=zero"
        )

        var candidateMBR = Data()
        candidateMBR.append(artifact.mbrPayload)
        candidateMBR.append(snapshot.mbr.suffix(72))

        try confirmUnmounted()
        report(
            HelperWorkflowLocalizationKeys.windowsInstallMacUSBootWritingStageTwo,
            "macUSBoot StageTwo write started: lba=1-5, bytes=\(artifact.stageTwo.count)"
        )
        do {
            try device.write(artifact.stageTwo, offset: 512)
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.stageTwoWrite(error.localizedDescription)
        }
        report(
            HelperWorkflowLocalizationKeys.windowsInstallMacUSBootWritingStageTwo,
            "macUSBoot StageTwo synchronization started: fsync+F_FULLFSYNC"
        )
        do {
            let synchronizationMode = try device.synchronize()
            report(
                HelperWorkflowLocalizationKeys.windowsInstallMacUSBootWritingStageTwo,
                "macUSBoot StageTwo synchronization completed: \(synchronizationMode.diagnosticDescription)"
            )
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.stageTwoSynchronization(error.localizedDescription)
        }
        do {
            let readback = try device.read(offset: 512, count: artifact.stageTwo.count)
            guard readback == artifact.stageTwo else {
                throw HelperWorkflowWindowsMacUSBootFailure.stageTwoReadback("byte comparison mismatch")
            }
            report(
                HelperWorkflowLocalizationKeys.windowsInstallMacUSBootWritingStageTwo,
                "macUSBoot StageTwo readback verified: bytes=\(readback.count), sha256=verified"
            )
        } catch let failure as HelperWorkflowWindowsMacUSBootFailure {
            throw failure
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.stageTwoReadback(error.localizedDescription)
        }

        try confirmUnmounted()
        report(
            HelperWorkflowLocalizationKeys.windowsInstallMacUSBootWritingMBR,
            "macUSBoot MBR write started: lba=0, bytes=512, preservedBytes=440-511"
        )
        do {
            try device.write(candidateMBR, offset: 0)
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.mbrWrite(error.localizedDescription)
        }
        report(
            HelperWorkflowLocalizationKeys.windowsInstallMacUSBootWritingMBR,
            "macUSBoot MBR synchronization started: fsync+F_FULLFSYNC"
        )
        do {
            let synchronizationMode = try device.synchronize()
            report(
                HelperWorkflowLocalizationKeys.windowsInstallMacUSBootWritingMBR,
                "macUSBoot MBR synchronization completed: \(synchronizationMode.diagnosticDescription)"
            )
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.mbrSynchronization(error.localizedDescription)
        }
        do {
            let readback = try device.read(offset: 0, count: 512)
            guard readback == candidateMBR else {
                throw HelperWorkflowWindowsMacUSBootFailure.mbrReadback("candidate MBR comparison mismatch")
            }
            report(
                HelperWorkflowLocalizationKeys.windowsInstallMacUSBootWritingMBR,
                "macUSBoot MBR readback verified: bytes=512, preservedBytes=verified"
            )
        } catch let failure as HelperWorkflowWindowsMacUSBootFailure {
            throw failure
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.mbrReadback(error.localizedDescription)
        }

        try verifyProtectedRanges(candidateMBR: candidateMBR, initialGap: snapshot.gap)
    }

    private func readInitialSnapshot() throws -> HelperWorkflowWindowsMacUSBootDiskSnapshot {
        do {
            return HelperWorkflowWindowsMacUSBootDiskSnapshot(
                mbr: try device.read(offset: 0, count: 512),
                gap: try device.read(
                    offset: 512,
                    count: HelperWorkflowWindowsMacUSBootLayoutValidator.protectedGapSectorCount * 512
                ),
                blockCount: device.blockCount
            )
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.targetAccess(error.localizedDescription)
        }
    }

    private func verifyProtectedRanges(candidateMBR: Data, initialGap: Data) throws {
        report(
            HelperWorkflowLocalizationKeys.windowsInstallMacUSBootVerifying,
            "macUSBoot final protected-range verification started"
        )
        do {
            let finalMBR = try device.read(offset: 0, count: 512)
            let finalGap = try device.read(
                offset: 512,
                count: HelperWorkflowWindowsMacUSBootLayoutValidator.protectedGapSectorCount * 512
            )
            guard finalMBR == candidateMBR,
                  finalGap.prefix(artifact.stageTwo.count) == artifact.stageTwo,
                  finalGap.dropFirst(artifact.stageTwo.count) == initialGap.dropFirst(artifact.stageTwo.count) else {
                throw HelperWorkflowWindowsMacUSBootFailure.mbrReadback("final protected-range verification mismatch")
            }
            report(
                HelperWorkflowLocalizationKeys.windowsInstallMacUSBootVerifying,
                "macUSBoot protected ranges verified: mbr=verified, stageTwo=verified, bytes440-511=preserved, lba6-2047=unchanged"
            )
        } catch let failure as HelperWorkflowWindowsMacUSBootFailure {
            throw failure
        } catch {
            throw HelperWorkflowWindowsMacUSBootFailure.mbrReadback(error.localizedDescription)
        }
    }
}
