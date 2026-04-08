# Finish and Cleanup Contract

## Finish Screen Behavior

Finish screen must report:
- success/failure/cancel,
- relevant final metrics/status,
- cleanup result state.

## Cleanup Determinism

Cleanup ownership and ordering must remain deterministic.
Fallback cleanup UX should remain explicit for failure cases.

Downloader-specific cleanup behavior is detailed in `docs/reference/features/downloader/DOWNLOADER.md`.

## Logging and Diagnostics

Cleanup logs should include:
- requested cleanup scope,
- cleanup executor (app/helper),
- result and error details when cleanup fails.

## Update Trigger

Update when finish result semantics or cleanup sequencing/ownership changes.
