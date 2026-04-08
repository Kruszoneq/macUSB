# Analysis and Compatibility Contract

## Detection Source of Truth

Analysis flags are the source of truth for workflow branch selection.
Unsupported detection outcomes must be clearly surfaced and must block unsupported paths.

## Current Supported Routing Families

- modern
- legacy
- restore-legacy
- PPC
- Sierra-specific
- Catalina-specific
- Mavericks-specific

Panther remains explicitly unsupported.

## Special Blocking Rule

For `.cdr` and `.iso` sources:
- if the image is already manually mounted in macOS,
- analysis must stop and instruct user to unmount and retry.

## Logging and Diagnostics

Analysis should log:
- selected source type,
- detected compatibility family/flags,
- explicit block reasons (for example mounted image conflict).

## Update Trigger

Update when detection heuristics, compatibility mapping, or blocking logic changes.
