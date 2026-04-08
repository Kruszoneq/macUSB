# App Runtime Overview

This file defines high-level runtime scope and global contracts.

## Purpose and Scope

`macUSB` creates bootable macOS/OS X/Mac OS X installer media from `.dmg`, `.iso`, `.cdr`, and `.app` sources.

Primary runtime goals:
- detect installer type/version and route to the correct workflow,
- safely prepare target USB media,
- execute privileged operations through helper architecture,
- keep the user flow guided and non-technical.

## Runtime Boundaries

- Process/workflow rules for agents are in `docs/AGENTS.md`.
- Runtime behavior is distributed across `docs/reference/*`.
- Feature-specific deep details live in dedicated references (`DOWNLOADER.md`, `HELPER.md`, etc.).

## Cross-Feature Invariants

- Downloader changes must not modify USB creation logic.
- USB creation changes must not modify downloader logic.
- Analysis routing remains the source of truth for workflow branch selection.
- Destructive operations must remain explicitly confirmed by user.

## Update Trigger

Update this file when app purpose, scope, or global runtime boundaries change.
