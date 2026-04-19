# Analysis and Compatibility Contract

Current implementation scope includes:

- macOS analysis path (primary, workflow-driving),
- Linux image recognition fallback path (analysis-only, no install flow).

Linux-specific behavior details are documented in:

- `docs/reference/features/analysis/LINUX_ANALYSIS_FLOW.md`

## Detection Source of Truth

Analysis flags are the source of truth for workflow branch selection.
Unsupported detection outcomes must be clearly surfaced and must block unsupported paths.

For Linux fallback:

- detection is considered successful when Linux is recognized, including unknown distro case,
- recognition result is informational-only and must not unlock install workflow,
- detected Linux state may present dedicated Linux icon resource (`linux.icns`) in analysis UI.

## Current Supported Routing Families

- modern
- legacy
- restore-legacy
- PPC
- Sierra-specific
- Catalina-specific
- Mavericks-specific

Panther remains explicitly unsupported.

Linux fallback routing is out of installer families:

- recognized Linux distro,
- Linux with unknown distro (`Linux - nierozpoznana dystrybucja`).

## Special Blocking Rule

For `.cdr` and `.iso` sources:
- if the image is already manually mounted in macOS,
- analysis must stop and instruct user to unmount and retry.

This rule applies to both macOS and Linux fallback paths.

## Logging and Diagnostics

Analysis should log:
- selected source type,
- detected compatibility family/flags,
- explicit block reasons (for example mounted image conflict).

Linux fallback should additionally log:

- fallback transition from macOS detection to Linux detection,
- fallback transition from mounted detection to `bsdtar` detection when needed,
- parsed Linux details (`distro`, `version`, `edition`, `arch`, `isARM`),
- evidence summary used for recognition,
- archive-reader diagnostics relevant to bounded execution (`bsdtar` timeout/errors).

## Update Trigger

Update when detection heuristics, compatibility mapping, or blocking logic changes.
