# Finish and Cleanup Contract

## Finish Screen Behavior

Finish screen must report:
- success/failure/cancel,
- relevant final metrics/status,
- cleanup result state.
- for a macOS installer classified as prerelease during analysis, keep the separate `BETA` badge visible beside the normalized system name; its tint follows the finish result card tone.
- for Linux workflow failures, show a localized warning card (orange tone) with localized title + localized error description mapped from helper failure context (not raw helper error text).
- Windows WIM conversion preflight/export-directory failures use the localized presentation defined in [Windows WIM Failure and Cleanup](#windows-wim-failure-and-cleanup).
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
- Standard and forced eject attempts own a USB-eject token from `diskutil` launch through the final success, unavailable, Spotlight-blocked, or failure state.
- debug finish routes keep the eject card visible with a disabled `DEBUG` action.

Result, cleanup, completion duration, guidance, ejection cards/actions, and USB completion notifications use the `FinishUSB` localization table. `LinuxWorkflowErrorMapper` carries finish-owned keys for final error cards; neutral verification mismatch/short-read keys are shared with manual raw images, while generic Linux/raw-image verification descriptions have separate identifiers. The disabled debug eject action displays a verbatim `DEBUG` literal without a catalog entry. Catalog ownership is defined in `docs/reference/platform/LOCALIZATION_CONTRACT.md`.

## Cleanup Determinism

Cleanup ownership and ordering must remain deterministic.
Fallback cleanup UX should remain explicit for failure cases.
For Windows BIOS creation, macUSBoot owns one final whole-disk mount attempt after its raw-write transaction. A mount failure is logged as a warning and does not turn an otherwise verified installation into a failure; normal temporary-file cleanup and finalization continue afterward.
App-termination path must execute centralized source-image cleanup for Windows/Linux workflows:
- tracked source ISO image entities are force-detached on app termination (final shutdown step),
- this applies regardless of active screen (`analysis`, `summary`, `progress`, `finish`) to prevent stale mounted installer images after app exit.
- An idle termination runs the centralized cleanup exactly once before exit. Failure to remove temporary files, discover tracked source images, or detach an image is logged and produces an error termination result, but does not cancel termination.
- Application termination first closes read-only discovery admission and cancels its owned child with bounded termination/cleanup. Destructive helper pipelines and the user-requested finish eject command retain their separate ownership.
- Finish-screen cleanup, emergency installation cleanup, downloader cleanup, tracked-image detach, and termination cleanup own cleanup-operation tokens for their full execution.

Downloader-specific cleanup behavior is detailed in `docs/reference/features/downloader/DOWNLOADER.md`.

### Windows WIM Failure and Cleanup

The helper uses shared `HelperWindowsWimErrorLocalizationKey` identifiers in the existing workflow-result `errorMessage` field for three conversion preparation failures:

| Error key under `finish.windows.error.wim_export` | Failure point |
| --- | --- |
| `insufficient_space.description` | `windows_prepare_source`, before target formatting, when known temporary capacity is below the estimate |
| `directory_creation.description` | `windows_split_wim`, after formatting and file copy, when export-directory preparation fails |
| `directory_ownership.description` | `windows_split_wim`, after formatting and file copy, when assignment to the requester's UID/group fails |

The finish screen resolves these keys from `FinishUSB.xcstrings`. Required/available bytes, system errors, paths, and requester UID remain English diagnostic context. Failures from the export or split command itself use the generic stage-aware command error, including its exit status, last output line when available, and arguments; they are not mapped to these three localized preparation errors.

Once export-directory preparation succeeds, a `defer` attempts to remove the directory when the split stage returns or throws, including on command failure or observed cancellation. This removal ignores its own error. Normal success, WIM failure, and cancellation also reach helper best-effort cleanup of the overall work directory; a removal failure there is logged and does not independently change the workflow result. Cleanup ordering is deterministic, but successful removal is not guaranteed.

Export and splitting use the existing cancellable command path. Cancellation returns the cancelled result after the command terminates and the helper observes cancellation. Temporary cleanup does not roll back USB formatting or remove partially copied files/SWM parts. A failed or cancelled target must therefore be treated as incomplete media.

The export layout, capacity estimates, diagnostic events, and verification limits are defined in [Windows WIM Splitting](../windows/WINDOWS_WIM_SPLITTING.md).

## Logging and Diagnostics

Cleanup logs should include:
- requested cleanup scope,
- cleanup executor (app/helper),
- result and error details when cleanup fails,
- finish-eject mode (`standard` or `force`) and Spotlight classification when applicable.

Finish cleanup, duration/result, and eject diagnostics retain the selected `[USB_WORKFLOW]` label and use English `AppLogging` messages. Finish cleanup records its app executor, requested mount-point detach and temporary path, detach exit status, temporary-file removal or skip/failure, and final duration/result/cleanup status. Forwarded helper diagnostics retain the same workflow label followed by `[HELPER]`; app-run `hdiutil` and `diskutil` diagnostics have no helper source tag. Raw `stderr` and system error descriptions remain attached to the labeled diagnostic line. The result and error cards continue to use localized UI text.

Allowed application termination records cleanup, temporary-directory removal, helper XPC disconnection, and termination-operation start/finish with English `[APP]` lines. After these lines, the app records an `[APP]` separator and a final success or cleanup-error line. Protected-operation details remain available in blocked-termination diagnostics.

## Update Trigger

Update when finish result semantics or cleanup sequencing/ownership changes.
