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
  - when standard eject fails and `stderr` identifies `mds_stores`, show a localized orange Spotlight warning card above the eject action and replace the action with force eject,
  - force eject immediately with `diskutil eject force /dev/diskX`, without an additional confirmation alert,
  - on successful standard or force eject, transition to the same localized success confirmation card,
  - on force-eject failure, show a localized error card and allow force-eject retry,
  - on any other eject failure, show the existing localized generic error card and allow standard retry,
  - keep raw `stderr` in installation logs only; never expose it in finish-screen UI.
- debug finish routes keep the eject card visible with a disabled `DEBUG` action.

## Cleanup Determinism

Cleanup ownership and ordering must remain deterministic.
Fallback cleanup UX should remain explicit for failure cases.
For Windows BIOS creation, macUSBoot owns one final whole-disk mount attempt after its raw-write transaction. A mount failure is logged as a warning and does not turn an otherwise verified installation into a failure; normal temporary-file cleanup and finalization continue afterward.
App-termination path must execute centralized source-image cleanup for Windows/Linux workflows:
- tracked source ISO image entities are force-detached on app termination (final shutdown step),
- this applies regardless of active screen (`analysis`, `summary`, `progress`, `finish`) to prevent stale mounted installer images after app exit.

Downloader-specific cleanup behavior is detailed in `docs/reference/features/downloader/DOWNLOADER.md`.

## Logging and Diagnostics

Cleanup logs should include:
- requested cleanup scope,
- cleanup executor (app/helper),
- result and error details when cleanup fails,
- finish-eject mode (`standard` or `force`) and Spotlight classification when applicable.

## Update Trigger

Update when finish result semantics or cleanup sequencing/ownership changes.
