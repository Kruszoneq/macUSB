# USB Validation and Capacity Contract

## Capacity Rules

Before installer recognition completes, required size in UI is unresolved (`-- GB`).

Thresholds:
- major version `<= 14`: UI `16 GB`, technical threshold `15_000_000_000` bytes
- major version `>= 15`: UI `32 GB`, technical threshold `28_000_000_000` bytes

Proceed must remain blocked until selected target passes validation.

## APFS Safety Rule

If selected target is APFS:
- proceed remains blocked,
- user is instructed to reformat manually in Disk Utility.

In PPC flow, specialized target formatting behavior must not be forced through standard assumptions.

## Logging and Diagnostics

Validation logs should include:
- computed required threshold,
- selected target capacity,
- final validation decision and block reason.

## Update Trigger

Update when thresholds, generation split, or APFS blocking behavior changes.
