# App Runtime Overview

This file defines high-level runtime scope and global contracts.

## Purpose and Scope

`macUSB` creates bootable USB media for:

- macOS/OS X/Mac OS X installers from `.dmg`, `.iso`, `.cdr`, and `.app` sources,
- supported Windows families from original `.iso` images using a boot-mode-aware BIOS or UEFI workflow,
- recognized Linux `.iso` images using the shared analysis and installation flow,
- manually selected raw `.iso` and `.img` images written directly to USB without content analysis.

Manual raw-image writing is an exceptional Tools-menu path. It reuses the existing Linux `dd` workflow and SHA-256 write verification, but carries app-only presentation state so the UI does not describe the source as Linux. It is not part of standard source selection or analysis fallback: selecting `.iso` through the standard `Choose` action still runs normal macOS/Windows/Linux analysis. Modified Windows images are outside the tested workflow contract; source-image selection and provenance remain the user's responsibility.

Primary runtime goals:

- detect installer type/version and route to the correct workflow,
- resolve supported Windows boot modes and preserve the selected mode through helper execution,
- safely prepare target USB media,
- execute privileged operations through helper architecture,
- keep the user flow guided and non-technical.

The Help menu provides diagnostic-log export through its menu item and the `Option-L` keyboard shortcut.

## Runtime Boundaries

- Process/workflow rules for agents are in `docs/AGENTS.md`.
- Runtime behavior is distributed across `docs/reference/*`.
- Feature-specific deep details live in dedicated references (`DOWNLOADER.md`, `HELPER.md`, etc.).

## Cross-Feature Invariants

- Downloader changes must not modify USB creation logic.
- USB creation changes must not modify downloader logic.
- Analysis routing remains the source of truth for workflow branch selection.
- Destructive operations must remain explicitly confirmed by user.
- App termination is coordinated through a process-wide active-operation registry.
- Quit requests and main-window close requests are rejected while analysis, USB creation, the downloader window, Rosetta installation, helper repair, long helper work, cleanup, or USB ejection is active.
- An allowed termination runs the idempotent application cleanup before exit; cleanup errors are logged and do not keep the app running.

## Active Operation and Termination Model

- Every protected operation owns an idempotent token from its actual start to its terminal result.
- Multiple and nested tokens are valid, including USB creation plus helper work plus helper cleanup.
- A blocked quit shows one generic localized warning and records the active operation kinds, contexts, identifiers, and durations in diagnostics.
- Repeated quit requests activate the existing warning instead of creating additional alerts.
- The warning does not expose a cancellation action or redirect the user to workflow cancellation.

## Update Trigger

Update this file when app purpose, scope, or global runtime boundaries change.
