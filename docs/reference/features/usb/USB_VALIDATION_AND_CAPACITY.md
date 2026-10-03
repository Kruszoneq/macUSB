# USB Validation and Capacity Contract

## Capacity Rules

Before installer recognition completes, required size in UI is unresolved (`-- GB`).

For every supported macOS, Linux, Windows, and manually selected raw-image workflow:

- the selected `.dmg`, `.iso`, `.cdr`, or `.img` file contributes its logical file size; a selected `.app` contributes the sum of regular-file sizes inside the bundle, without following symbolic links,
- the exact minimum is `ceil(source bytes × 105 / 100)`, using checked integer arithmetic,
- the UI shows the smallest decimal-GB class from `2`, `4`, `8`, `16`, `32`, `64`, and further doublings that is at least the exact minimum,
- target admission compares actual target bytes with the exact minimum, not the displayed class; an unreadable target capacity fails validation.

Source-size resolution runs off the main thread for `.app` bundles. Zero, unreadable, or unrepresentable source sizes use a documented fallback and trigger a user-facing alert. For macOS major version `>= 15`, the fallback is the `32 GB` class with a `28_000_000_000`-byte validation threshold. Older macOS, Linux, Windows, and manual raw-image workflows use the `16 GB` class with a `15_000_000_000`-byte threshold.

The hardware-requirement card continues to show the drive class. If an Option-selected volume is too small, its error card instead shows the exact required capacity in decimal GB rounded upward to one fractional digit; the byte threshold remains authoritative.

Proceed must remain blocked until selected target passes validation.

## macOS Target Selection and Formatting

Recognized macOS workflows use physical whole-disk (`diskX`) targets by default:
- target labels use `diskX - <size> - <USB standard>`,
- APFS and other existing formats remain selectable,
- every non-PPC whole-disk target is passed to automatic GPT/HFS+ preparation with the `mac_USB` label,
- PPC remains a specialized whole-disk path and keeps its existing APM/HFS+ formatting.

Physical whole-disk targets are the shared base snapshot for every supported workflow, and their preparation starts independently when the analysis screen appears. The picker never uses mounted volumes as its default target source or exposes a target list before the initial snapshot is ready. A second macOS Option snapshot is prepared from the same physical-disk enumeration and adds only eligible mounted GPT/HFS+ volumes. Pressing or releasing Option switches between these prepared in-memory presentations immediately. Workflow eligibility changes and the periodic analysis-screen refresh may still trigger a new enumeration.

For standard `createinstallmedia` workflows, holding Option on the analysis screen enables a mixed target list:
- every physical `diskX` target remains in the list,
- eligible mounted HFS+ volumes from a GPT disk are inserted directly after their matching physical `diskX` target,
- APFS and other volumes from that disk are omitted,
- disks without an eligible GPT/HFS+ volume remain unchanged in the list,
- the physical-disk and mixed lists are prepared together, so pressing or releasing Option switches the presented list immediately without another disk enumeration,
- releasing Option always restores the physical-disk list; the mixed list is never latched,
- changing the presented list does not clear, replace, or hide the name of an already selected disk or volume,
- a selected eligible volume still skips automatic preformat when the user proceeds, even after Option is released.

The Option volume override applies only to standard `createinstallmedia` workflows. PPC, restore-legacy, and Mavericks restore workflows expose and pass only physical `diskX` targets. If analysis changes into one of these workflows while a volume from that disk was selected earlier, selection is normalized to its parent physical disk. PPC then uses its dedicated APM/HFS+ formatting, while restore workflows use GPT/HFS+ preparation.

Linux, Windows, and manual raw-image workflows keep their existing physical whole-disk selection behavior.

## Physical Target Discovery and Refresh

The shared physical target snapshot is built as follows:

- use `diskutil list -plist external` to obtain external whole-disk identifiers,
- read `diskutil info -plist /dev/diskX` for each candidate,
- bind info metadata to the requested `DeviceIdentifier` and require `WholeDisk=true` (the diskutil plist key, distinct from IOMedia's `Whole` registry property),
- include only external, physical USB devices,
- when `AllowExternalDrives` is disabled, exclude non-removable external USB disks,
- retain per-target identity and capacity evidence from the same scan for admission,
- sort targets by their `diskX` identifier.

This physical enumeration does not depend on a readable or mounted macOS volume. A connected USB medium that macOS cannot mount can therefore still appear directly as a selectable whole-disk target.

The analysis screen starts discovery when it appears or the app becomes active. Its `0.5 s` UI tick still updates Option state, but physical discovery is throttled to at most once every `2.5 s` while the screen is visible and the app is active. Refreshes are serialized per analysis owner; duplicate requests are skipped instead of queued. Hiding the screen, navigating to installation, or deactivating the app cancels its current discovery. Workflow-state changes may request a refresh through the same throttle.

Read-only discovery commands share a single active subprocess slot. stdout and stderr are drained together with nonblocking reads while the child runs, retaining at most `4 MiB` per stream. Queries have a `5 s` deadline, then a `0.5 s` termination grace before SIGKILL and another bounded cleanup period. If exit cannot be observed, the child keeps the slot and further commands are rejected until Foundation observes/reaps exit. These bounds cover the child execution and stream-draining path; a kernel operation blocking process launch or mounted-volume metadata cannot be forcibly completed by this userspace policy.

The analysis-only `USBTargetDiscoveryService` returns a structured result: complete (including a valid empty list), partial with device-specific issues, failed enumeration with a process/parsing/data category, runner busy, or normal cancellation. Per-query failures distinguish timeout, output limit, launch/read failure and exit status. Existing `USBDriveLogic` entry points used outside analysis retain their prior behavior.

`AnalysisUSBDiscoveryState` separates activity (idle, checking, waiting, suspended) from the outcome and the last presentation snapshot. Each target has separate identity/capacity evidence; `USBTargetReadiness` distinguishes no selection, unresolved requirement, unverified, insufficient known capacity and ready. The compatibility capacity Boolean properties are derived from this state. Unknown capacity is never zero or a confirmed insufficient-space result.

A routine refresh retains current evidence and never clears selection or replaces the list with a spinner. A failure to read one device does not discard independently verified targets: a selected target with known sufficient capacity can proceed despite another device's failure. A failed or malformed whole enumeration retains the previous presentation but invalidates its admission evidence. Returning to the screen or activating the application obtains new evidence; lifecycle cancellation is neutral, not a drive failure. Preference changes invalidate old-policy evidence and discard in-flight results captured with a different `AllowExternalDrives` value.

Unreadable entries are shown only when current registry evidence independently confirms an external physical USB storage device at that BSD name. The registry probe stops at the nearest block-storage device and requires USB/external protocol characteristics; a cached name or `diskX` identifier is insufficient. Non-removable devices still follow `AllowExternalDrives`. A device whose USB type cannot be confirmed is omitted and logged as a partial issue. Confirmed USB media with unreadable required data remains visible as unavailable. Registry entry identities are sampled before/after info reads and again before snapshot publication; volumes also carry their own current registry identity bound to that physical parent. Reuse of a BSD name with a different identity cannot automatically reauthorize a selection.

Whole-disk and Option-volume capacity come from current scan metadata; missing, invalid or nonpositive bytes block admission with a read/data reason. Eligible GPT/HFS+ mounted volumes are prepared without another diskutil query. Mounted-volume metadata failures remain explicit, and physical targets remain independently usable. Workflow changes normalize a volume only to its own physical parent. A missing target is removed from the list and is never recreated from cache or replaced by another disk.

Errors add a contextual card in the existing USB section and expose Check Again. A verified-alternative hint appears only when a current target actually has known sufficient capacity. A deliberate attempt to select an unavailable target opens an app-icon NSAlert with a specific localized explanation, Check Again and Close. Automatic loss of selected-target readiness only blocks Continue and updates the card/log; it never opens that alert. Successful checking clears the error presentation and restores readiness with the same selection when its identity remains valid. Selecting a replacement identity requires deliberate reselection. The handoff property rechecks admission against the current snapshot, preference and exact byte requirement. Continue additionally performs an asynchronous read-only registry identity/capacity check (and fresh GPT/HFS+ volume checks for Option targets), with no subprocess, new prompt or normal-flow status. Repeated Continue actions share one owned request; stale selection/source/lifecycle callbacks are discarded. Thus a retained presentation alone cannot hand off a disconnected, replaced or unreadable target even if another child is holding the runner slot. An unavailable selection uses explicit actions in the existing selector position so choosing the same failed row again always reaches the alert path; recovery restores the standard Picker.

The final handoff check updates the selected target's evidence as well as its readiness. A failed check therefore remains blocked on deliberate reselection until a successful new read replaces that evidence; a known capacity change is retained as a byte value rather than a generic error.

Repeated requests are skipped rather than queued. While an owned child remains in the shared runner slot, the UI shows a waiting state; normal periodic ticks resume checking after the slot is released. Cancelled generations cannot overwrite current state. IOKit parent traversal owns a separate retained starting reference and releases every acquired ancestor on all return paths.

Run the standalone resource/scheduling regression checks with `bash scripts/TestUSBDiscovery.sh`. They compile production utilities and use mocked registry ownership plus synthetic child processes; they do not launch macUSB, invoke diskutil or modify media.

The Option presentation additionally reads mounted external, non-network volumes and keeps only volumes that:

- belong to a physical USB whole disk from the shared snapshot,
- use a GPT partition scheme,
- use HFS+,
- satisfy the same removable/external-drive preference policy.

UI rules:
- while the initial target snapshot is being prepared, analysis UI shows the neutral waiting state,
- when at least one physical USB target is present but source recognition is still pending, the neutral waiting card remains visible instead of target-selection controls,
- after the initial snapshot finishes with no eligible physical targets, the UI shows `Nie wykryto nośnika USB`,
- physical targets use the concise label `diskX - <size> - <USB standard>`,
- Option-selected HFS+ volumes use the mounted-volume label `diskXsY - <size> - <USB standard> - <volume name>`,
- releasing Option restores the physical presentation; if an eligible volume remains selected, the picker keeps that one selected-volume entry visible until the selection changes,
- when workflow routing changes to PPC, restore-legacy, or Mavericks, any selected volume is normalized to its parent physical `diskX` target.

In PPC flow, specialized target formatting behavior must not be forced through standard assumptions.

## Logging and Diagnostics

Analysis-screen target discovery, selection, and capacity-validation diagnostics use English `AppLogging` lines with the `USB` stage and the recognized workflow suffix (`MACOS`, `PPC`, `WINDOWS`, `LINUX`, or `RAW`). Before a workflow is known, the base `USB` stage is used.

Validation logs should include:
- computed required threshold,
- selected target capacity,
- final validation decision and block reason.

Selecting a different whole disk or volume logs one capacity-validation result with target kind and identifier, required and actual bytes, and whether the target meets the requirement. An unreadable capacity is logged as unverified, with the read failure as the reason. Periodic refreshes only log readiness transitions rather than repeating unchanged selection validation.

Discovery additionally logs scan generation and trigger, preference, full command/arguments and device identifier, duration, result category, exit code, parsing/missing-data failures, device qualification/omission, known capacities, cancellation, termination escalation, retained/released subprocess slots and rejected stale results. Tool output snippets retain at most 2 KiB per stream, within the existing 4 MiB capture limit. Per-analysis diagnostic history is bounded to 256 keys; identical periodic events are coalesced for 60 seconds with a suppressed-occurrence count, and changed/recovered outcomes are emitted immediately. Readiness loss and recovery include the required bytes and the prior/new decision.

Issue #128's observed watchdog panic motivated investigation; neither PR #129 nor these admission/diagnostic changes establish its cause or a confirmed system-panic fix.

## Update Trigger

Update when thresholds, generation split, target-selection policy, or preformat eligibility changes.
