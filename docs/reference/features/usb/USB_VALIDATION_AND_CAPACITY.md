# USB Validation and Capacity Contract

## Capacity Rules

Before installer recognition completes, required size in UI is unresolved (`-- GB`).

macOS thresholds:
- major version `<= 14`: UI `16 GB`, technical threshold `15_000_000_000` bytes
- major version `>= 15`: UI `32 GB`, technical threshold `28_000_000_000` bytes

Linux, Windows, and manual raw `.iso`/`.img` selection use the same source-image thresholds. Apply the first matching upper limit:

- source size up to `900_000_000` bytes: UI `1 GB`, technical threshold `900_000_000` bytes
- source size up to `1_800_000_000` bytes: UI `2 GB`, technical threshold `1_800_000_000` bytes
- source size up to `3_600_000_000` bytes: UI `4 GB`, technical threshold `3_600_000_000` bytes
- source size up to `7_300_000_000` bytes: UI `8 GB`, technical threshold `7_300_000_000` bytes
- source size up to `14_700_000_000` bytes: UI `16 GB`, technical threshold `14_700_000_000` bytes
- source size up to `29_400_000_000` bytes: UI `32 GB`, technical threshold `29_400_000_000` bytes
- source size up to `58_800_000_000` bytes: UI `64 GB`, technical threshold `58_800_000_000` bytes

Sources above `58_800_000_000` bytes currently remain in the top `64 GB` class.

Manual raw-image selection intentionally keeps this existing class-based policy; it does not add exact byte-size capacity validation.

Fallback for Linux and Windows source-size resolution:
- if source image size cannot be resolved, required capacity falls back to `16 GB` (instead of unresolved `-- GB`).

Proceed must remain blocked until selected target passes validation.

## macOS Target Selection and Formatting

Recognized macOS workflows use physical whole-disk (`diskX`) targets by default:
- target labels use `diskX - <size> - <USB standard>`,
- APFS and other existing formats remain selectable,
- every non-PPC whole-disk target is passed to automatic GPT/HFS+ preparation with the `mac_USB` label,
- PPC remains a specialized whole-disk path and keeps its existing APM/HFS+ formatting.

Physical whole-disk targets are the shared base snapshot for every supported workflow, and their preparation starts independently when the analysis screen appears. The picker never uses mounted volumes as its default target source or exposes a target list before the initial snapshot is ready. A second macOS Option snapshot is prepared from the same physical-disk enumeration and adds only eligible mounted GPT/HFS+ volumes. Pressing or releasing Option switches between these prepared in-memory presentations immediately. Workflow eligibility changes and the periodic analysis-screen refresh may still trigger a new enumeration.

For standard `createinstallmedia` workflows, holding Option on the analysis screen enables a mixed target list:
- every physical `diskX` target remains in the list,
- eligible mounted HFS+ volumes from a GPT disk are inserted directly after their matching physical `diskX` target,
- APFS and other volumes from that disk are omitted,
- disks without an eligible GPT/HFS+ volume remain unchanged in the list,
- the physical-disk and mixed lists are prepared together, so pressing or releasing Option switches the presented list immediately without another disk enumeration,
- releasing Option always restores the physical-disk list; the mixed list is never latched,
- changing the presented list does not clear, replace, or hide the name of an already selected disk or volume,
- a selected eligible volume still skips automatic preformat when the user proceeds, even after Option is released.

The Option volume override applies only to standard `createinstallmedia` workflows. PPC, restore-legacy, and Mavericks restore workflows expose and pass only physical `diskX` targets. If analysis changes into one of these workflows while a volume from that disk was selected earlier, selection is normalized to its parent physical disk. PPC then uses its dedicated APM/HFS+ formatting, while restore workflows use GPT/HFS+ preparation.

Linux, Windows, and manual raw-image workflows keep their existing physical whole-disk selection behavior.

## Physical Target Discovery and Refresh

The shared physical target snapshot is built as follows:

- use `diskutil list -plist external` to obtain external whole-disk identifiers,
- read `diskutil info -plist /dev/diskX` for each candidate,
- include only external, physical USB devices,
- when `AllowExternalDrives` is disabled, exclude non-removable external USB disks,
- cache whole-disk capacity from the same enumeration for target-capacity validation,
- sort targets by their `diskX` identifier.

This physical enumeration does not depend on a readable or mounted macOS volume. A connected USB medium that macOS cannot mount can therefore still appear directly as a selectable whole-disk target.

The analysis screen starts discovery when it appears and requests refresh every `0.5 s`. Refreshes are serialized so a new enumeration does not start while the previous one is running. Workflow-state changes may request an additional refresh; the current snapshot remains authoritative until a completed refresh replaces it.

The Option presentation additionally reads mounted external, non-network volumes and keeps only volumes that:

- belong to a physical USB whole disk from the shared snapshot,
- use a GPT partition scheme,
- use HFS+,
- satisfy the same removable/external-drive preference policy.

UI rules:
- while the initial target snapshot is being prepared, analysis UI shows the neutral waiting state,
- when at least one physical USB target is present but source recognition is still pending, the neutral waiting card remains visible instead of target-selection controls,
- after the initial snapshot finishes with no eligible physical targets, the UI shows `Nie wykryto nośnika USB`,
- physical targets use the concise label `diskX - <size> - <USB standard>`,
- Option-selected HFS+ volumes use the mounted-volume label `diskXsY - <size> - <USB standard> - <volume name>`,
- releasing Option restores the physical presentation; if an eligible volume remains selected, the picker keeps that one selected-volume entry visible until the selection changes,
- when workflow routing changes to PPC, restore-legacy, or Mavericks, any selected volume is normalized to its parent physical `diskX` target.

In PPC flow, specialized target formatting behavior must not be forced through standard assumptions.

## Logging and Diagnostics

Validation logs should include:
- computed required threshold,
- selected target capacity,
- final validation decision and block reason.

## Update Trigger

Update when thresholds, generation split, target-selection policy, or preformat eligibility changes.
