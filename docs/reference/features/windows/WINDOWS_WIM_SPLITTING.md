# Windows WIM Splitting Contract

This reference describes the current `install.wim` preparation path, including conversion from the WIM format that permits solid resources. The surrounding stage graph is defined in [USB Creation Workflows](../usb/USB_CREATION_WORKFLOWS.md).

## Split Decision and Input Scope

The FAT32 per-file limit used by both app analysis and helper preparation is `4_294_967_295` bytes (`2^32 - 1`). Splitting is required only when the resolved `install.wim` is strictly larger than that limit.

Analysis checks file size and computes `windowsWillSplitWIM` for summary presentation and the tool prerequisite gate. It does not inspect WIM compression or check temporary export space. The helper resolves the source again in `windows_prepare_source` and makes the execution decision before target formatting.

The split lookup uses `sources` / `Sources` and `install.wim` / `INSTALL.WIM`; it does not implement an arbitrary case-insensitive filename index.

| Source payload | Current handling |
| --- | --- |
| `install.wim` at or below the FAT32 limit, including a solid-format WIM | Copied without export or splitting; this path does not require wimlib |
| Oversized `install.wim` not classified as solid-format | Excluded from file copy and split directly to USB |
| Oversized `install.wim` classified as solid-format | Excluded from file copy, exported to a temporary non-solid LZX WIM, then split to USB |
| `install.esd` | Copied without conversion when it fits; an oversized ESD is rejected by the non-WIM file-size scan |
| Existing `.swm` parts | Copied as source files without export or re-splitting; oversized parts are subject to the non-WIM file-size scan |

The helper scans regular, non-hidden source files for FAT32 violations and exempts only the resolved `install.wim`. Conversion support does not provide a general solution for oversized `boot.wim`, ESD, or other payload files.

Both the app prerequisite probe and the helper resolve an executable `wimlib-imagex`; the helper checks again when a split is required. These checks establish executable presence, not tool version or successful command execution. No minimum tested wimlib version is recorded in the runtime references.

## Solid-Format Classification

`isWindowsWimSolid` reads the first 20 bytes, requires the `MSWIM\0\0\0` signature, and interprets bytes 12–15 as a little-endian version number. Version `0xE00` selects the conversion path.

This is a format-version criterion, not a scan for actual solid resources or an inspection of the compression flags. The wimlib format permits both solid resources and LZMS compression with this version; solid mode and the LZMS algorithm are separate properties. A version match may therefore select conversion even when the archive contains no solid resources. Open/read failure, a short header, or a signature/version mismatch returns `false`; this detector does not separately report an invalid WIM. Subsequent wimlib execution can still fail on that input.

The term solid describes compressing multiple file resources together. It is not determined by the `.wim` / `.esd` extension or by UUP provenance. wimlib rejects direct splitting of archives containing solid resources, which is why this path exports a non-solid archive first.

The tested source contract remains original Microsoft Windows ISO images. UUP-generated or repacked images may exercise the conversion code, but that does not place them within the tested compatibility guarantee defined in [Windows Analysis](../analysis/WINDOWS_ANALYSIS_FLOW.md#source-image-trust-boundary).

## Temporary Space Preflight

For an oversized WIM classified as solid-format, `windows_prepare_source` estimates required export space as `Int64(Double(installWimSizeBytes) * 1.6)`. This truncates the positive estimate to whole bytes; it does not measure the eventual LZX output size.

The helper queries the parent of `request.tempWorkPath`, preferring `volumeAvailableCapacityForImportantUsage` and falling back to `volumeAvailableCapacity`. Known available capacity below the estimate stops the workflow before `windows_prepare_target`. An unavailable capacity value is logged as `-1` and does not block execution. Equality with the estimate passes.

The app supplies `FileManager.default.temporaryDirectory/macUSB_temp` as the work directory. Export space is needed on that temporary volume, independently of free space on USB. The check reserves no space and is not repeated immediately before export, which occurs after formatting and file copy. The `1.6` factor is a heuristic, so a passing check does not guarantee that conversion will fit or that space will remain available.

USB admission continues to use the source ISO size plus 5%. It does not account for expansion when converting solid resources to non-solid LZX. The resulting SWM payload can therefore exceed the admitted target capacity; see [Windows WIM Capacity Limits](../usb/USB_VALIDATION_AND_CAPACITY.md#windows-wim-capacity-limits).

## Commands and Output Layout

For an ordinary oversized WIM, the command is:

```text
wimlib-imagex split <source-install.wim> <USB-sources>/install.swm 3800
```

For a WIM classified as solid-format, the commands are:

```text
wimlib-imagex export <source-install.wim> all <tempWorkPath>/windows_wim_export/install-nonsolid.wim --compress=LZX
wimlib-imagex split <tempWorkPath>/windows_wim_export/install-nonsolid.wim <USB-sources>/install.swm 3800
```

The commands above show argument structure; angle-bracket values are placeholders. `all` exports every image index, retaining the multi-edition payload rather than selecting a single edition. `--compress=LZX` explicitly creates a non-solid destination. The source ISO is not rewritten.

The helper removes any existing `windows_wim_export` directory, creates a fresh one, and assigns its owner/group to the requester when a positive requester UID is supplied. SWM output goes directly to the verified target volume's source subdirectory, with names `install.swm`, `install2.swm`, `install3.swm`, and so on. The converted WIM remains on the temporary volume during splitting.

`3800` is a requested part size in MiB (`3_984_588_800` bytes), not decimal MB. wimlib cannot divide an individual file resource between parts, so a sufficiently large resource can make a part exceed the requested size. This parameter alone does not guarantee that every possible input produces FAT32-compatible parts.

## Progress and Diagnostics

Export and splitting share `windows_split_wim`, its title, and its status key. There is no separate conversion stage or conversion-specific UI status. Ordinary splitting spans overall progress `80–95%`; conversion uses `80–87.5%` for export and `87.5–95%` for splitting. The halves are fixed weights, not estimates of elapsed or remaining time.

The commands use `LC_ALL=C` and `LANG=C`. The parser accepts integer percentages in `(N%) written` or `(N%) done` output. Other lines remain diagnostics and do not advance parsed progress; stage completion advances progress after the command returns successfully.

The displayed disk speed is sampled for the target whole disk through `iostat`. During export the output is written to the temporary volume, so low or zero target activity does not indicate that conversion has stopped. This value does not measure export throughput.

Diagnostic events include the split/classification decision, temporary-volume path and required/available bytes, conversion output path, directory creation/ownership failures, and streamed command output. Finish error presentation and cleanup limits are defined in [Windows WIM Failure and Cleanup](../usb/FINISH_AND_CLEANUP.md#windows-wim-failure-and-cleanup).

## Verification Limits

Both wimlib commands must exit successfully. Neither command uses `--check` or `--include-integrity`, and the helper performs no separate WIM integrity pass.

After a split, `windows_verify_media` checks the presence of `sources/install.swm` or `Sources/install.swm`, in addition to boot-mode-specific structure and any generated answer file. It does not enumerate the complete SWM set, compare image indexes with the source, independently enforce part sizes, or hash/read back the WIM payload. A successful workflow is not evidence of a full archive integrity check or a completed Windows Setup boot/install test.

## Manual Verification Coverage to Record

This table describes useful manual coverage, not completed test results. Record the app build, macOS/architecture, `wimlib-imagex --version`, source identity and provenance, source/converted sizes, temporary free space, target capacity, command outcomes, and whether Windows Setup sees the expected editions.

| Scenario | Behavior to verify |
| --- | --- |
| Ordinary oversized WIM | Direct split, numbered parts, and a usable installer |
| Oversized solid-format WIM with multiple images | Export followed by split, retained edition list, and temporary cleanup |
| WIM at/below the FAT32 limit | Copy without a split stage, including solid-format input |
| Oversized ESD or another non-WIM file | Failure during source preparation before USB formatting |
| Known temporary capacity below the estimate | Localized preflight failure before USB formatting |
| Unknown temporary capacity or space exhaustion during export | No preflight block for unknown capacity; command failure and cleanup when export cannot complete |
| LZX expansion exceeding target capacity | Split/write failure; no guarantee from ISO-based admission |
| Cancellation during export or splitting | Cancelled result, attempted temporary cleanup, and incomplete USB treated as unusable |

Solid/UUP fixtures outside the original-Microsoft-ISO contract must be identified as such in any validation record. Evidence is still needed before describing a particular wimlib version or fixture as tested.

## Implementation and External References

- `macUSB/Features/Analysis/Logic/Windows/AnalysisLogicWindowsLifecycle.swift` — app split expectation.
- `macUSB/Shared/Services/Windows/WindowsToolchainProbeService.swift` — app executable probe.
- `macUSBHelper/Workflow/Windows/HelperWorkflowWindowsSourceLogic.swift` — helper split decision, header classification, and temporary-space preflight.
- `macUSBHelper/Workflow/Windows/HelperWorkflowWindowsStages.swift` — copy exclusion, export, split, and export-directory preparation.
- `macUSBHelper/Workflow/Windows/HelperWorkflowWindowsWimSplitProgressParsing.swift` — command progress parsing.
- `macUSBHelper/Workflow/Windows/HelperWorkflowWindowsValidationLogic.swift` — target payload-marker checks.
- [wimlib export manual](https://www.wimlib.net/man1/wimexport.html) — image selection and explicit solid-to-non-solid export.
- [wimlib split manual](https://wimlib.net/man1/wimsplit.html) — MiB units, part naming, and indivisible-resource limitation.
- [wimlib header definitions](https://github.com/ebiggers/wimlib/blob/master/include/wimlib/header.h) — version and compression semantics.
- [wimlib split implementation](https://github.com/ebiggers/wimlib/blob/master/src/split.c) — rejection of archives containing solid resources.

## Update Trigger

Update this reference when split thresholds, input lookup, solid-format classification, export-space policy, commands, progress weights, or WIM verification change.
