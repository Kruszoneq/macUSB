# Finish and Cleanup Contract

## Finish Screen Behavior

Finish screen must report:
- success/failure/cancel,
- relevant final metrics/status,
- cleanup result state.
- for Linux workflow failures, show a localized warning card (orange tone) with localized title + localized error description mapped from helper failure context (not raw helper error text).
- after successful creation, show a localized eject-action card for safe ejection of the selected target whole-disk (`diskX`).
- eject card behavior:
  - use accent tone and an eject symbol,
  - run safe eject for whole-disk target,
  - disable action when target is no longer available,
  - on successful eject, transition to localized success confirmation card,
  - on eject failure, show localized error card and allow retry.
- debug finish routes keep the eject card visible with a disabled `DEBUG` action.

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
