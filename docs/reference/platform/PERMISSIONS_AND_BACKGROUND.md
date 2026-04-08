# Permissions and Background Contract

## Runtime Prerequisites

The app requires:
- Full Disk Access for `macUSB`,
- Allow in the Background approval for helper operation.

Startup and helper readiness flows must surface missing prerequisites.

## Current Runtime Behavior

- Full Disk Access is checked on startup and surfaced via UI/alerts when missing.
- Helper background approval is checked at startup and in ensure-ready/repair flows.
- Missing prerequisites are visible and can block reliable helper operations.
- External drive support defaults to disabled on launch/termination unless explicitly enabled.

## Logging and Diagnostics

Important startup and helper-approval milestones should be logged via `AppLogging`.
Logs should clearly indicate which prerequisite is missing and what the app did next.

## Update Trigger

Update when permission prompts, startup gating order, or background-approval handling changes.
