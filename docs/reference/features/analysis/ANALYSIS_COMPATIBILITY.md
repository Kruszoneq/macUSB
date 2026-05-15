# Analysis and Compatibility Contract

Current implementation scope includes:

- macOS analysis path (primary, workflow-driving),
- Windows image recognition fallback path (between macOS and Linux),
- Linux image recognition fallback path with USB-creation handoff.

Linux-specific behavior details are documented in:

- `docs/reference/features/analysis/LINUX_ANALYSIS_FLOW.md`

Windows-specific behavior details are documented in:

- `docs/reference/features/analysis/WINDOWS_ANALYSIS_FLOW.md`

## Detection Source of Truth

Analysis flags are the source of truth for workflow branch selection.
Unsupported detection outcomes must be clearly surfaced and must block unsupported paths.

For Windows fallback:

- fallback entry is limited to `.iso` sources,
- fallback runs only when macOS installer metadata is not detected from mounted image,
- Windows detection uses mounted-image metadata only (no weak volume-label fallback),
- recognized Windows result may be marked unsupported by support gate,
- support gate for current app workflow is:
  - desktop: **Windows family >= 8 AND EFI markers present**,
  - server: **Windows Server family >= 2012 AND EFI markers present**,

For Linux fallback:

- fallback entry is limited to `.iso` sources,
- detection is considered successful when Linux is recognized, including unknown distro case,
- recognized Linux result unlocks shared install flow (`UniversalInstallationView -> CreationProgressView -> FinishUSBView`),
- detected Linux state may present dedicated Linux icon resource (`linux.icns`) in analysis UI.
- manual Linux force from `Opcje -> Pomiń analizowanie pliku -> Linux` is treated as Linux-recognized state for install handoff only when selected source is `.iso`.

## Current Supported Routing Families

- modern
- legacy
- restore-legacy
- PPC
- Sierra-specific
- Catalina-specific
- Mavericks-specific
- Linux raw-copy

Panther remains explicitly unsupported.

Linux fallback routing includes:

- recognized Linux distro,
- Linux with unknown distro (`Linux - nierozpoznana dystrybucja`).
- manually forced Linux (`Linux`).

Windows fallback routing includes:

- recognized Windows families:
  - desktop: `XP`, `Vista`, `7`, `8`, `8.1`, `10`, `11`,
  - server: `Server 2003`, `Server 2008 R2`, `Server 2012`, `Server 2012 R2`, `Server 2016`, `Server 2019`, `Server 2022`, `Server 2025`,
- optional Service Pack extraction when deterministically available (for legacy families),
- architecture normalization to `x86` / `ARM`,
- unsupported result for `XP` / `Vista` / `7` regardless of EFI artifacts,
- unsupported result for `Server 2003` / `Server 2008 R2` regardless of EFI artifacts,
- unsupported result for any family missing required EFI markers.
- unsupported requirement info message is family-aware:
  - desktop variant: `Windows 8 + EFI`,
  - server variant: `Windows Server 2012 + EFI`.

## Special Blocking Rule

For `.cdr` and `.iso` sources:
- if the image is already manually mounted in macOS,
- analysis must stop and instruct user to unmount and retry.

This rule applies to macOS image analysis and additionally protects Linux fallback entry for `.iso`.
It also applies to Windows fallback entry for `.iso`.

## Global Image Analysis Timeout

For `.dmg`, `.iso`, and `.cdr` sources:

- the full image-analysis session is guarded by a global 20-second timeout,
- if recognition does not complete within 20 seconds, analysis is force-finished as unrecognized (`Nie rozpoznano instalatora`),
- when timeout is hit, app must force-detach the mounted source image used for analysis (if present),
- timeout finish keeps existing UI behavior (no new messages/views), and blocks supported-flow routing as for other unrecognized outcomes,
- delayed callbacks from expired analysis sessions must be ignored and must not overwrite state after timeout.

Global app-termination cleanup invariant for ISO analysis:

- when analysis touches `.iso` source, app registers source-image path for centralized exit cleanup,
- on app termination, centralized cleanup force-detaches tracked Linux/Windows source-image entities (by `image-path` match from `hdiutil info -plist`),
- this termination cleanup runs even if user exits during analysis before workflow start.

For Linux fallback on `.iso`:

- cleanup scope includes all image entities captured from `hdiutil info -plist` for the selected `image-path`,
- cleanup is not limited to one mount-point; it must include all captured `dev-entry` and fallback `mount-point` detach attempts,
- Linux entity cleanup must run on Linux success, Linux failure, timeout, cancel, and reset paths.

## USB Unreadable Target Hint (Non-blocking)

During analysis screen USB target area:
- if a physical external USB disk is connected but unreadable for macOS mount stack, show a warning hint with Disk Utility guidance,
- this hint does not replace supported-target validation (capacity/APFS) for readable drives,
- generic `Nie wykryto nośnika USB` message is suppressed when unreadable USB hint is active and picker has no readable targets,
- Disk Utility action inside this hint remains interactive regardless of analysis-state gating for USB selection controls.
- this hint is shown only for macOS-target flow; Linux-target flow suppresses this hint and uses physical `diskX` selection.
- in macOS flow, this hint is shown only after macOS routing is detected (it stays hidden before system detection).

## Logging and Diagnostics

Analysis should log:
- selected source type,
- detected compatibility family/flags,
- explicit block reasons (for example mounted image conflict),
- image-analysis timeout start/finish events for `.dmg`/`.iso`/`.cdr`,
- timeout-triggered image detach result (success/failure + mount path),
- ignored stale callbacks when an expired image-analysis session returns results after timeout.

Linux fallback should additionally log:

- fallback transition from macOS detection to Linux detection,
- fallback transition from mounted detection to `bsdtar` detection when needed,
- parsed Linux details (`distro`, `version`, `edition`, `arch`, `isARM`),
- Linux gate signals and classification source fields (`rule`, `matched_signal`, `version_source`),
- evidence summary used for recognition,
- Linux attach-session snapshot plus per-entity cleanup result and residual summary,
- archive-reader diagnostics relevant to bounded execution (`bsdtar` timeout/errors),
- install handoff readiness (`linuxSourceURL` present, capacity computed).
- manual-force diagnostics when Linux is forced from menu.

Windows fallback should additionally log:

- fallback transition from macOS detection to Windows detection,
- parsed Windows details (`family`, `service_pack`, `arch`, `isARM`),
- support gate decision (`is_supported`, `support_reason`, `has_efi`),
- evidence summary used for recognition.

## Update Trigger

Update when detection heuristics, compatibility mapping, or blocking/handoff logic changes.
