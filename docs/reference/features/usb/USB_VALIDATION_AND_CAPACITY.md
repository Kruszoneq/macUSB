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

For standard `createinstallmedia` workflows, holding Option on the analysis screen enables a mixed target list:
- a GPT disk with mounted HFS+ volumes is replaced by those HFS+ volumes,
- APFS and other volumes from that disk are omitted,
- disks without an eligible GPT/HFS+ volume remain selectable as physical `diskX` targets,
- the physical-disk and mixed lists are prepared together, so pressing or releasing Option switches the presented list immediately without another disk enumeration,
- releasing Option always restores the physical-disk list; the mixed list is never latched,
- changing the presented list does not clear or replace an already selected disk or volume,
- a selected eligible volume still skips automatic preformat when the user proceeds, even after Option is released.

Linux, Windows, and manual raw-image workflows keep their existing physical whole-disk selection behavior.

## Unreadable USB Guidance

Before source recognition, unreadable-media detection may contribute to the neutral waiting state in the USB section. After a supported macOS, Linux, Windows, or manual raw-image workflow is recognized, physical USB enumeration makes an otherwise unreadable medium directly selectable as `diskX`.

Detection policy:
- use `diskutil list -plist external` to enumerate connected external whole disks,
- use mounted volume enumeration to map currently mountable/readable disks,
- classify as unreadable USB only when all of the following are true:
  - disk is external (`Internal`/`OSInternalMedia` is false),
  - disk bus is `USB` (`BusProtocol == USB`),
  - disk is physical (`VirtualOrPhysical == Physical`),
  - no mounted volume maps to that whole disk.

UI rules:
- when any USB is physically connected but system recognition is still pending, analysis UI shows a neutral waiting card in the USB section instead of target-selection messages,
- physical targets use the concise label `diskX - <size> - <USB standard>`,
- Option-selected HFS+ volumes retain the existing mounted-volume label.

In PPC flow, specialized target formatting behavior must not be forced through standard assumptions.

## Logging and Diagnostics

Validation logs should include:
- computed required threshold,
- selected target capacity,
- final validation decision and block reason.

## Update Trigger

Update when thresholds, generation split, target-selection policy, or preformat eligibility changes.
