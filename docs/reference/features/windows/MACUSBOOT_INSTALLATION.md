# macUSBoot Installation Contract

## Scope

macUSBoot is the final BIOS-enablement transaction in the Windows USB workflow. It runs only when `windowsBootMode == bios`, after `windows_verify_media` and before `windows_cleanup_temp`. The UEFI workflow never loads or writes this artifact and retains its existing stage graph.

The app must confirm that the active helper advertises `windows.macusboot.v1` before showing destructive confirmation. The helper advertises this capability only after resolving and fully validating the bundled artifact. Capability versions describe functional contract compatibility, while app version/build fingerprint changes trigger helper re-registration. The app queries once, performs one controlled helper reload when the capability is missing, the artifact is unavailable, or the IPC contract is stale, and queries once more. Failure after that recovery keeps start blocked with helper-repair guidance.

## Bundled Artifact Contract

The application bundle contains exactly this directory:

`Contents/Resources/macUSBoot/`

- `manifest.json`
- `macUSBoot-v1.0.bin`
- `macUSBoot-v1.0.bin.sha256`

The helper rejects missing or additional entries, symbolic links, non-regular files, unsupported manifest values, malformed headers, checksum-file drift, size drift, or any component hash mismatch.

The helper resolves its absolute executable path from the running process, locates the enclosing `.app/Contents`, and then reads `Resources/macUSBoot`. It must not derive the bundle location from `CommandLine.arguments[0]`, because `SMAppService` may launch a `BundleProgram` using a relative program identifier.

Pinned values:

| Component | Offset | Size | SHA-256 |
| --- | ---: | ---: | --- |
| Complete container | 0 | 3032 | `729a0852f86a5c7da58dc807f9920159cfc09f97661f0ce4099c80f290253585` |
| MBR payload | 32 | 440 | `1eb3bf65781393f8bccbb04c4ad30bb8acc6aed8e3396f150b764e789f816c54` |
| StageTwo | 472 | 2560 | `be00204b4c465eb0f09daa7e245cedea741762964e2c9fa20792c19eeb53e11f` |

Supported format is schema/container/StageTwo version `1`, container header size `32`, StageTwo header size and entry offset `16`, StageTwo sector count `5`, and zero flags. Container and StageTwo magic, offsets, lengths, jump displacement, and `MEND` trailer are validated before target access.

## Media and Disk Preconditions

BIOS source and copied target media must contain, case-insensitively:

- `BOOTMGR`,
- `boot/BCD`,
- `sources/boot.wim`.

The raw transaction accepts only:

- a whole-disk character device opened read/write, exclusive, and close-on-exec,
- 512-byte logical sectors,
- MBR signature `0x55AA`,
- inactive first partition entry with type `0x0B`, first LBA `2048`, nonzero sector count, and an extent inside the device,
- empty partition entries 2 through 4,
- LBA 1...5 containing only zeros or the exact pinned StageTwo,
- LBA 6...2047 containing only zeros.

Any foreign or partially matching data in the protected gap is a hard failure. The helper does not overwrite it.

## Transaction Ordering

The helper starts a Disk Arbitration approval guard for the whole disk and its partitions, unmounts the whole disk, verifies that no volumes remain mounted, and opens `/dev/rdiskX` exclusively.

The write transaction is deliberately ordered:

1. Read and validate the complete MBR plus LBA 1...2047 snapshot.
2. Build a candidate sector 0 from artifact bytes 0...439 and original target bytes 440...511, preserving disk signature, partition table, and MBR signature.
3. Reconfirm that the target remains unmounted.
4. Write StageTwo to LBA 1...5, require a successful `fsync`, attempt `F_FULLFSYNC`, then fully read back and compare all bytes.
5. Reconfirm that the target remains unmounted.
6. Write the complete candidate MBR sector, require a successful `fsync`, attempt `F_FULLFSYNC`, then fully read back and compare all bytes.
7. Read the full protected range again and verify the MBR, StageTwo, preserved bytes 440...511, and unchanged LBA 6...2047.

There is no rollback, automatic retry, or checkpoint continuation. StageTwo is written before sector 0 so a failure cannot advertise a new MBR boot path before the second-stage payload has been durably verified.

Some raw character devices and USB storage bridges do not support `F_FULLFSYNC`. After a successful `fsync`, `ENOTTY` or `ENOTSUP` from `F_FULLFSYNC` selects a logged `fsync-only` fallback and the mandatory byte-for-byte readback continues. Every other synchronization error remains fatal.

## Cancellation, Release, and Remount

Cancellation is disabled in the progress UI and helper cancellation requests return `false` without setting cancellation state while `windows_install_macusboot` is active.

Every terminal path closes the raw descriptor and releases the Disk Arbitration guard. The stage then issues exactly one logical `diskutil mountDisk` attempt. A remount failure is logged as a warning but does not invalidate a completed, fully verified transaction. Workflow cleanup and finalization continue normally.

## Progress and Diagnostics

The stage key is `windows_install_macusboot`. Semantic localized phase keys are:

- `helper.workflow.windows_install_macusboot.checking_artifact`,
- `helper.workflow.windows_install_macusboot.unmounting`,
- `helper.workflow.windows_install_macusboot.checking_layout`,
- `helper.workflow.windows_install_macusboot.writing_stage_two`,
- `helper.workflow.windows_install_macusboot.writing_mbr`,
- `helper.workflow.windows_install_macusboot.verifying`,
- `helper.workflow.windows_install_macusboot.remounting`.

Live diagnostics include full logical diskutil commands with safe arguments, exit codes and bounded output, artifact identity, raw-device geometry and lifecycle, guard lifecycle, layout decisions, sync/readback phases, and remount result. Binary contents are never logged.

Failures use stable diagnostic categories for invalid artifact, target access, incompatible layout, occupied protected gap, StageTwo write/sync/readback, and MBR write/sync/readback. App-side presentation maps any failure at this stage to the localized macUSBoot installation error instead of exposing raw helper diagnostics.

## Verification Boundary

Minimum implementation verification is a successful macOS Debug build plus bundle inspection for the exact resource set and pinned hashes. A destructive smoke test requires a specifically identified disposable USB target and separate user confirmation; it must not be inferred from implementation approval.

## Update Trigger

Update this document when capability identifiers, bundled artifact metadata, accepted disk layout, write ordering, cancellation/remount semantics, stage/status keys, or BIOS/UEFI routing changes.
