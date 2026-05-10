# Windows Analysis Flow and Rules

This document defines Windows-source detection behavior in `SystemAnalysisView` analysis stage.

## Scope

Windows detection is a fallback path in analysis between macOS and Linux.

- Primary path remains macOS installer detection.
- Windows path runs for `.iso` only when macOS installer metadata is not detected from mounted image.
- If Windows is not recognized, flow continues to Linux fallback.
- This iteration does not add Windows USB-creation workflow.

## Trigger and Entry

Windows fallback is entered when all conditions are met:

- selected source is `.iso`,
- source is not blocked by pre-mounted image guard,
- macOS installer `.app` metadata was not resolved from mounted image.

Runtime sequence:

- app attempts standard image attach/read path used by macOS analysis,
- if mounted source path is available and macOS was not recognized, Windows fallback runs on mounted content,
- if Windows fallback returns no recognized family, Linux fallback continues (mounted first, then `bsdtar` path as implemented),
- if mount step timed out and mounted path is unavailable, Windows fallback is skipped and Linux fallback continues.

## Detection Inputs

Detection uses bounded metadata reads from mounted image only.

- `sources/idwbinfo.txt` (branch and architecture hints),
- `sources/cversion.ini` (additional branch/version hint),
- image payload markers:
  - `sources/install.wim`,
  - `sources/install.esd`,
  - `sources/install.swm`,
- XP markers:
  - top-level `WIN51*`,
  - top-level `I386`.

No recursive unpacking and no weak volume-label-only recognition path.

## EFI Support Gate

For this app iteration, a detected Windows image is treated as workflow-supported only when both are true:

- detected family is one of:
  - desktop: `8`, `8.1`, `10`, `11`,
  - server: `Server 2012`, `Server 2012 R2`, `Server 2016`, `Server 2019`, `Server 2022`, `Server 2025`,
- required EFI markers are present:
  - `efi` directory,
  - and at least one EFI boot marker:
    - `bootmgr.efi`, or
    - `efi/microsoft/boot/cdboot.efi`, or
    - `efi/boot/bootx64.efi`, or
    - `efi/boot/bootaa64.efi`.

Unsupported policy:

- `XP`, `Vista`, `7` are always unsupported even if EFI artifacts exist.
- `Server 2003` and `Server 2008 R2` are always unsupported even if EFI artifacts exist.
- desktop `8+` without required EFI markers is unsupported.
- server `2012+` without required EFI markers is unsupported.

## Classification Rules

Detection result produces:

- family (`XP`, `Vista`, `7`, `8`, `8.1`, `10`, `11`, `Server 2003`, `Server 2008 R2`, `Server 2012`, `Server 2012 R2`, `Server 2016`, `Server 2019`, `Server 2022`, `Server 2025`),
- optional Service Pack string (`SP1`, `SP2`, `SP3`) when deterministic,
- normalized architecture (`x86` / `ARM` / `unknown`),
- support decision and reason.

Family mapping (current implementation contract):

- XP: `WIN51*` + `I386` markers,
- Vista: `lh_sp*` / `vista` branch hints,
- 7: `win7*` branch hints,
- 8.1: `winblue*` branch hints,
- 8: `win8*` branch hints,
- 10: `vb_release` branch hint,
- 11: `ge_release` branch hint.
- Server 2003: `WIN51*` + `I386` with server signal.
- Server 2008 R2: `win7sp1_*` with server signal.
- Server 2012: `win8*` with server signal.
- Server 2012 R2: `winblue*` with server signal.
- Server 2016: `rs1_release` with server signal.
- Server 2019: `rs5_release` with server signal.
- Server 2022: `fe_release` with server signal.
- Server 2025: `ge_release` with server signal.

Service Pack extraction:

- XP: from `WIN51*.SPx`,
- Vista/7: from branch SP hint (`sp1` / `sp2` / `sp3`),
- Server 2003: from `WIN51*.SPx`,
- Server 2008 R2: from branch SP hint (`sp1`),
- for unresolved or conflicting legacy signals: no Service Pack suffix.

Architecture normalization:

- `amd64`, `x86_64`, `x86`, `i386` -> `x86`,
- `arm64`, `aarch64`, `bootaa64` marker -> `ARM`.

## UI Output and Gating

Display format:

- desktop: `Windows <Family>`
- server: `Windows Server <Version>`
- append ` - Service Pack <nr>` only when Service Pack is deterministic,
- append ` (ARM)` only for ARM result.

Fallback icon behavior:

- when no dedicated Windows file icon is available, use SF Symbol fallback chain:
  - `pc`,
  - fallback `desktopcomputer`.

Current workflow gating:

- supported Windows detection is shown as successful detection state in analysis card,
- proceed to installation remains blocked in this iteration (no Windows creation flow yet),
- unsupported Windows detection follows unsupported presentation path,
- unsupported requirement info message is family-aware:
  - desktop uses `Windows 8 + EFI` requirement wording,
  - server uses `Windows Server 2012 + EFI` requirement wording.

## Logging Contract

When Windows fallback runs, logs include:

- transition entry from macOS detection to Windows detection,
- parsed details (`family`, `service_pack`, `arch`, `isARM`),
- support gate summary (`is_supported`, `support_reason`, `has_efi`),
- evidence list used for classification.

## Non-goals

- No Windows creation flow in this iteration.
- No release-channel marketing version extraction (`22H2`, `25H2`).
- No fallback based only on volume label when mounted metadata is unavailable.

## Update Trigger

Update this file when Windows detection heuristics, EFI support gate, display format, or handoff behavior changes.
