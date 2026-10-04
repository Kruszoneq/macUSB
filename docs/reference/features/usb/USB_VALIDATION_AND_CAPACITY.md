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
- target labels use `diskX - <size> - <USB standard>` for USB or `diskX - <size> - SD CARD` for SD cards,
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

- use `diskutil list -plist physical` to obtain physical whole-disk identifiers, including cards in built-in SD readers,
- read `diskutil info -plist /dev/diskX` for each candidate,
- bind info metadata to the requested `DeviceIdentifier` and require `WholeDisk=true` (the diskutil plist key, distinct from IOMedia's `Whole` registry property),
- include only external physical USB devices or confirmed removable SD cards; native SD transport may report an internal reader,
- when `AllowExternalDrives` is disabled, exclude non-removable external USB disks,
- retain per-target identity and capacity evidence from the same scan for admission,
- sort targets by their `diskX` identifier.

This physical enumeration does not depend on a readable or mounted macOS volume. A connected USB or SD medium that macOS cannot mount can therefore still appear directly as a selectable whole-disk target.

SD identification uses the exact `Secure Digital` transport reported by diskutil/IOKit. A USB-connected card is also identified as SD when its current IOMedia or nearest block-storage device exposes the system `SD.icns` icon. Device names, volume labels, and generic reader names are not used as type evidence. Readers that expose only generic USB storage remain supported USB targets with their USB label. Internal fixed disks and virtual devices are excluded; known unsupported registry transports are filtered before an info query. SD cards require confirmed removable status independently of `AllowExternalDrives`, so built-in readers do not require enabling external hard drives. Mounted SD volumes may report internal status and remain eligible for the Option override when GPT/HFS+ and removable checks pass.

The media kind follows whole disks, Option volumes, selection normalization and PPC handoff. It selects the verbatim hardware label `SD CARD` in analysis and summary and suppresses the USB 2.0 warning for identified SD cards. Final handoff rechecks SD kind and removable status alongside the existing identity/capacity verification. This enables writing a card; boot compatibility still depends on the destination hardware and image.

The analysis screen starts discovery when it appears or the app becomes active. Its `0.5 s` UI tick still updates Option state, but physical discovery is throttled to at most once every `2.5 s` while the screen is visible and the app is active. Refreshes are serialized per analysis owner; duplicate requests are skipped instead of queued. Hiding the screen, navigating to installation, or deactivating the app cancels its current discovery. Workflow-state changes may request a refresh through the same throttle.

Read-only discovery commands share a single active subprocess slot. stdout and stderr are drained together with nonblocking reads while the child runs, retaining at most `4 MiB` per stream. Queries have a `5 s` deadline, then a `0.5 s` termination grace before SIGKILL and another bounded cleanup period. If exit cannot be observed, the child keeps the slot and further commands are rejected until Foundation observes/reaps exit. These bounds cover the child execution and stream-draining path; a kernel operation blocking process launch or mounted-volume metadata cannot be forcibly completed by this userspace policy.

The analysis-only `USBTargetDiscoveryService` returns a structured result: complete (including a valid empty list), partial with device-specific issues, failed enumeration with a process/parsing/data category, runner busy, or normal cancellation. Per-query failures distinguish timeout, output limit, launch/read failure and exit status. Existing `USBDriveLogic` entry points used outside analysis retain their prior behavior.

`AnalysisUSBDiscoveryState` separates activity (idle, checking, waiting, suspended) from the outcome and the last presentation snapshot. Each target has separate identity/capacity evidence; `USBTargetReadiness` distinguishes no selection, unresolved requirement, unverified, insufficient known capacity and ready. The compatibility capacity Boolean properties are derived from this state. Unknown capacity is never zero or a confirmed insufficient-space result.

A routine refresh retains current evidence and never clears selection or replaces the list with a spinner. Each successful target-specific identity/capacity read records monotonic uptime in its verification evidence; scan starts, other targets and final identity-only publication checks cannot renew that timestamp. Evidence is fresh for less than `20 s`. The existing `0.5 s` UI tick checks its age before the running-worker and occupied-runner guards, so a prolonged scan or blocked subprocess slot revokes readiness without another command loop. Twenty seconds allows several sequential queries with a `5 s` individual deadline plus scheduling/cleanup headroom; it is an admission freshness limit, not a deadline for the full scan. A larger or stalled scan can exceed it and safely block Continue until fresh evidence arrives. The handoff property independently checks the same age, and Continue retains its exact read-only identity/capacity verification.

Uncertain same-identity reads retain the last successful confirmation time without restoring failed capacity evidence; failures still block admission immediately, and prolonged uncertainty uses the availability card once that last confirmation expires. A failed whole enumeration likewise retains the presentation and its confirmation age. Expired confirmation retains the selected row and presentation but blocks Continue with `confirmationExpired`, never a claimed disconnection. The compact availability card appears above the destructive warning and uses the same warning surface, orange icon/title, secondary orange description, icon size and centered row alignment; both use symmetric contextual-card motion. The destructive warning remains visible whenever a target is selected, including application inactivity, rechecking, insufficient capacity and unavailable or expired evidence. Activity and readiness govern Continue availability independently of this warning; clearing the selection removes it. The generic discovery notice is suppressed for this selected-target condition. A successful scan of the same identity restores readiness automatically when capacity still fits; a changed identity remains blocked until deliberate reselection. Partial reads that cannot establish absence retain the selected row with failed admission evidence; a confirmed absence removes it. A failure to read one device does not discard independently verified targets: a selected target with known sufficient capacity can proceed despite another device's failure. A failed or malformed whole enumeration retains the previous presentation but invalidates its admission evidence. Returning to the screen or activating the application obtains new evidence; lifecycle cancellation is neutral, not a drive failure. Preference changes invalidate old-policy evidence and discard in-flight results captured with a different `AllowExternalDrives` value.

New unreadable entries are shown only when current registry evidence independently confirms an external physical USB storage device or a removable SD card at that BSD name. The registry probe stops at the nearest block-storage device and requires USB/external or Secure Digital/removable characteristics; a cached name or `diskX` identifier is insufficient to discover a new row. The previously selected row may be retained during an uncertain read, with failed admission evidence as described above. Non-removable USB devices still follow `AllowExternalDrives`; SD cards always require confirmed removable media. A device whose supported type cannot be confirmed is omitted and logged as a partial issue. Confirmed USB/SD media with unreadable required data remains visible as unavailable. Registry entry identities are sampled before/after info reads and again before snapshot publication; volumes also carry their own current registry identity bound to that physical parent. Reuse of a BSD name with a different identity cannot automatically reauthorize a selection.

Whole-disk and Option-volume capacity come from current scan metadata; missing, invalid or nonpositive bytes block admission with a read/data reason. Eligible GPT/HFS+ mounted volumes are prepared without another diskutil query. Mounted-volume metadata failures remain explicit, and physical targets remain independently usable. Workflow changes normalize a volume only to its own physical parent. A missing target is removed from the list and is never recreated from cache or replaced by another disk.

Errors add a contextual warning card in the existing USB section, styled like the destructive warning with matching typography, colors and icon sizing. Inline discovery and availability cards contain no retry button; periodic discovery handles recovery automatically. A verified-alternative hint appears only when a current target actually has known sufficient capacity. A deliberate attempt to select an unavailable target opens an app-icon NSAlert with a specific localized explanation, Check Again and Close. Automatic loss of selected-target readiness only blocks Continue and updates the card/log; it never opens that alert. Successful checking clears the error presentation and restores readiness with the same selection when its identity remains valid. Selecting a replacement identity requires deliberate reselection. The handoff property rechecks admission against the current snapshot, preference and exact byte requirement. Continue additionally performs an asynchronous read-only registry identity/capacity check (and fresh GPT/HFS+ volume checks for Option targets), with no subprocess, new prompt or normal-flow status. Repeated Continue actions share one owned request; stale selection/source/lifecycle callbacks are discarded. Thus a retained presentation alone cannot hand off a disconnected, replaced or unreadable target even if another child is holding the runner slot. An unavailable selection uses explicit actions in the existing selector position so choosing the same failed row again always reaches the alert path; recovery restores the standard Picker.

The final handoff check updates the selected target's evidence as well as its readiness. A failed check therefore remains blocked on deliberate reselection until a successful new read replaces that evidence; a known capacity change is retained as a byte value rather than a generic error.

Repeated requests are skipped rather than queued. While an owned child remains in the shared runner slot, the UI shows a waiting state; normal periodic ticks resume checking after the slot is released. Cancelled generations cannot overwrite current state. IOKit parent traversal owns a separate retained starting reference and releases every acquired ancestor on all return paths.

Run the standalone resource/scheduling regression checks with `bash scripts/TestUSBDiscovery.sh`. They compile production utilities and use mocked registry ownership plus synthetic child processes; they do not launch macUSB, invoke diskutil or modify media.

The Option presentation additionally reads mounted external, non-network volumes and keeps only volumes that:

- belong to a physical USB or SD whole disk from the shared snapshot,
- use a GPT partition scheme,
- use HFS+,
- satisfy the same removable/external-drive preference policy.

UI rules:
- while the initial target snapshot is being prepared, analysis UI shows the neutral waiting state,
- when at least one physical USB or SD target is present but source recognition is still pending, the neutral waiting card remains visible instead of target-selection controls,
- after the initial snapshot finishes with no eligible USB or SD physical targets, the UI shows `Nie wykryto nośnika USB`,
- physical USB targets use `diskX - <size> - <USB standard>`; SD targets use `diskX - <size> - SD CARD`,
- Option-selected HFS+ volumes use `diskXsY - <size> - <USB standard> - <volume name>` with `SD CARD` replacing the USB standard for SD cards,
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

Discovery logs the first snapshot and meaningful changes to ordered physical and Option lists, including target labels/URLs, identity, exact capacity, partition/format, qualification and per-device issues. Comparison excludes evidence timestamps, scan generation, PID and duration. Connect/disconnect, identity/capacity changes, readiness loss/recovery, preference changes, cancellation/resumption, manual retry and Continue verification remain observable. Unchanged successful scans, routine scan starts, individual query successes and ordinary subprocess-slot cleanup are silent. The 60-second periodic replay is removed.

Failures retain command/arguments, device, generation, duration, category, exit status and bounded output; termination escalation and retained-slot recovery remain diagnostic events. PID is excluded from process-event signatures. Identical persistent errors are suppressed until change/recovery, with the suppressed count attached to that transition. A successful query logs only recovery from its own error; manual retry explicitly emits bounded query diagnostics and a result even when unchanged. Tool snippets retain at most 2 KiB per stream within the existing 4 MiB capture limit. Per-analysis history remains bounded to 256 keys plus one semantic snapshot comparison. Readiness loss and recovery include required bytes and prior/new decisions.

Issue #128's observed watchdog panic motivated investigation; neither PR #129 nor these admission/diagnostic changes establish its cause or a confirmed system-panic fix.

## Update Trigger

Update when thresholds, generation split, target-selection policy, or preformat eligibility changes.
