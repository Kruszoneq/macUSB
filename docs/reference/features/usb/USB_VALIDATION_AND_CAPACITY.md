# USB Validation and Capacity Contract

## Capacity Rules

Before installer recognition completes, required size in UI is unresolved (`-- GB`).

Thresholds:
- major version `<= 14`: UI `16 GB`, technical threshold `15_000_000_000` bytes
- major version `>= 15`: UI `32 GB`, technical threshold `28_000_000_000` bytes
- Linux source size `<= 6_000_000_000` bytes: UI `8 GB`, technical threshold `6_000_000_000` bytes
- Linux source size `> 6_000_000_000` and `<= 14_000_000_000` bytes: UI `16 GB`, technical threshold `15_000_000_000` bytes
- Linux source size `> 14_000_000_000` bytes: UI `32 GB`, technical threshold `28_000_000_000` bytes

Proceed must remain blocked until selected target passes validation.

## APFS Safety Rule

If selected target is APFS:
- proceed remains blocked,
- user is instructed to reformat manually in Disk Utility.

## Unreadable USB Guidance

If at least one external USB medium is physically connected but has no readable/mountable macOS volume:
- analysis screen keeps the standard USB picker behavior for readable targets,
- an additional warning card is shown in USB section,
- warning copy instructs user to erase medium in Disk Utility,
- warning card exposes a direct action to open Disk Utility.
- warning card action must remain clickable even when USB selection UI is disabled by analysis state.

Detection policy:
- use `diskutil list -plist external` to enumerate connected external whole disks,
- use mounted volume enumeration to map currently mountable/readable disks,
- classify as unreadable USB only when all of the following are true:
  - disk is external (`Internal`/`OSInternalMedia` is false),
  - disk bus is `USB` (`BusProtocol == USB`),
  - disk is physical (`VirtualOrPhysical == Physical`),
  - no mounted volume maps to that whole disk.

UI suppression rule:
- when unreadable USB warning is shown and there are no readable targets in picker, do not show the generic `Nie wykryto nośnika USB` error card.

In PPC flow, specialized target formatting behavior must not be forced through standard assumptions.

## Logging and Diagnostics

Validation logs should include:
- computed required threshold,
- selected target capacity,
- final validation decision and block reason.

## Update Trigger

Update when thresholds, generation split, or APFS blocking behavior changes.
