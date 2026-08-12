# Analysis and Compatibility Contract

Current implementation scope includes:

- macOS analysis path (primary, workflow-driving),
- Windows image recognition fallback path (between macOS and Linux),
- Linux image recognition fallback path with USB-creation handoff.

Linux-specific behavior details are documented in:

- `docs/reference/features/analysis/LINUX_ANALYSIS_FLOW.md`

Windows-specific behavior details are documented in:

- `docs/reference/features/analysis/WINDOWS_ANALYSIS_FLOW.md`

## Detection Source of Truth

Analysis flags are the source of truth for workflow branch selection.
Unsupported detection outcomes must be clearly surfaced and must block unsupported paths.

Analysis owns a protected-operation token whenever `isAnalyzing` is active. The token covers supported, unsupported, failure, already-mounted-source, and global-timeout outcomes. Manual SHA-256 calculation uses a separate analysis token until completion, cancellation, failure, or sheet teardown. Starting analysis or applying a manual analysis override locks language changes for the current flow.

For selected macOS `.app` sources and macOS `.app` bundles found inside mounted `.dmg`, `.iso`, and `.cdr` sources:

- analysis must read installer metadata from `Contents/Info.plist`,
- prerelease state is detected from prerelease markers in `CFBundleDisplayName` (`Beta`, `Seed`, `Preview`, `Release Candidate`, or `RC`) and from the Apple seed-bundle identifier marker in `CFBundleIdentifier`,
- a detected prerelease installer keeps the normalized system name free of prerelease suffixes and exposes a separate `BETA` badge in the analysis result and every subsequent main-flow screen through finish,
- Golden Gate metadata is normalized to the user-facing name `macOS 27 Golden Gate`, regardless of the internal installer-app version, and Golden Gate is routed as a modern installer,
- analysis must inspect installer payload markers before accepting the app as a valid source:
  - `Contents/Resources/createinstallmedia` must exist as a file for standard app-installer workflows,
  - `Contents/SharedSupport/InstallESD.dmg` must exist as a file and is sufficient only for restore-legacy metadata (`Lion` / `Mountain Lion`, `10.7` / `10.8`),
- standard app-installer workflows inspect `Contents/Resources/createinstallmedia` locally through the system `CFBundleCopyExecutableArchitecturesForURL` API, without launching external tools or requiring Xcode Command Line Tools,
- CoreFoundation handles thin and Fat/Universal Mach-O formats; analysis normalizes the returned `x86_64` and ARM64 CPU types, treats `arm64e` as Apple Silicon, and fails closed for unreadable, unsupported, or non-Mach-O results,
- the physical Mac architecture is detected through `hw.optional.arm64` with a controlled `uname` fallback; compile-time or current-process architecture must not drive compatibility,
- Intel Mac plus ARM-only `createinstallmedia` is an unsupported result that blocks USB selection and cannot be bypassed through manual analysis skipping,
- an unreadable/unknown `createinstallmedia` architecture, or unknown physical host architecture when a decision is required, fails closed,
- Apple Silicon plus Intel-only `createinstallmedia` for Yosemite through Catalina creates a Rosetta summary requirement; universal and ARM-capable tools do not,
- Rosetta availability is probed by executing `/usr/bin/arch -x86_64 /usr/bin/true`; `EBADARCH`/`Bad CPU type in executable` means missing, and any other nonzero outcome is indeterminate,
- mounted images may accept legacy Mac OS X installer apps without these payload markers only when the mounted image exposes `System/Library/CoreServices/SystemVersion.plist` with `ProductUserVisibleVersion` from `10.3` through `10.6`; Panther remains an unsupported detection outcome,
- bundle identifier is diagnostic metadata only and must not be treated as proof that the app contains installer payload,
- invalid `.app` selections must keep the selected source visible but clear install-handoff state (`sourceAppURL`, detected icon, USB section, target selection, capacity result, and workflow flags),
- invalid `.app` bundles found inside mounted images must not set macOS install-handoff state; `.iso` sources may still continue into Windows/Linux fallback when no valid macOS app is accepted,
- explicitly recognized unsupported macOS outcomes, including Panther, remain unsupported detection results rather than generic invalid-app results.

For Windows fallback:

- fallback entry is limited to `.iso` sources,
- fallback runs only when macOS installer metadata is not detected from mounted image,
- Windows detection uses mounted-image metadata only (no weak volume-label fallback),
- Windows detection independently records case-insensitive BIOS and UEFI marker evidence,
- detected boot modes are filtered by family/architecture policy and handed to the installation summary together with the detected family,
- recognized Windows result may be marked unsupported by support gate,
- current summary-handoff support gate requires at least one eligible mode for a supported family:
  - `Vista`, `7`, `Server 2008 R2`: BIOS,
  - `8` through `10`, `Server 2012` through `Server 2022`: BIOS or UEFI,
  - `11`, `Server 2025`: UEFI,
  - `XP`, `Server 2003`: unsupported,

For Linux fallback:

- fallback entry is limited to `.iso` sources,
- detection is considered successful when Linux is recognized, including unknown distro case,
- recognized Linux result unlocks shared install flow (`UniversalInstallationView -> CreationProgressView -> FinishUSBView`),
- detected Linux state may present dedicated Linux icon resource (`linux.icns`) in analysis UI.
- manual Linux force from `Opcje -> Pomiń analizowanie pliku -> Linux` is treated as Linux-recognized state for install handoff only when selected source is `.iso`.
- raw Linux `.img` force from `Narzędzia -> Zapisz surowy obraz Linux (.img)...` is a separate exceptional entry point; it is not part of standard source selection or fallback detection and treats the selected `.img` as Linux-recognized without content inspection.

## Current Supported Routing Families

- modern
- legacy
- restore-legacy
- PPC
- Sierra-specific
- Catalina-specific
- Mavericks-specific
- Linux raw-copy

Panther remains explicitly unsupported.

Linux fallback routing includes:

- recognized Linux distro,
- Linux with unknown distro (`Linux - nierozpoznana dystrybucja`).
- manually forced Linux (`Linux`).
- manually forced raw Linux image (`Linux (.img)`).

Windows fallback routing includes:

- recognized Windows families:
  - desktop: `XP`, `Vista`, `7`, `8`, `8.1`, `10`, `11`,
  - server: `Server 2003`, `Server 2008 R2`, `Server 2012`, `Server 2012 R2`, `Server 2016`, `Server 2019`, `Server 2022`, `Server 2025`,
- optional Service Pack extraction when deterministically available (for legacy families),
- architecture normalization to `32-bit` / `64-bit` / `ARM` / `unknown`,
- BIOS detection from `bootmgr` + `boot/BCD` + `sources/boot.wim`, with additional diagnostic BIOS markers,
- UEFI detection from the existing EFI directory/boot-marker rule,
- eligible boot-mode mapping:
  - `Vista`, `7`, and `Server 2008 R2`: BIOS,
  - `8` through `10` and `Server 2012` through `Server 2022`: every detected mode,
  - `11` and `Server 2025`: UEFI only,
  - `XP` and `Server 2003`: no eligible modes,
  - ARM: UEFI only when otherwise eligible for its Windows family,
- unsupported result for `XP` and `Server 2003`,
- unsupported result for any otherwise supported family with no eligible boot mode,
- summary boot-mode presentation and pre-start behavior:
  - `Vista`, `7`, and `Server 2008 R2`: BIOS-only informational card,
  - `8` through `10` and `Server 2012` through `Server 2022`: segmented BIOS/UEFI control driven by eligible modes; UEFI is the dual-mode default and a single eligible mode locks the control,
  - `11` and `Server 2025`: existing UEFI-only informational card,
  - selected mode is session-only, logged, and sent through helper/XPC as required `windowsBootMode`,
  - BIOS selection runs the `windows.macusboot.v1` helper capability preflight before destructive confirmation; one controlled helper reload is attempted when needed, and start remains blocked with repair guidance only if the capability is still unavailable,
  - UEFI selection uses the existing Windows media-creation path without loading or installing macUSBoot.

## Special Blocking Rule

For `.cdr` and `.iso` sources:
- if the image is already manually mounted in macOS,
- analysis must stop and instruct user to unmount and retry.

This rule applies to macOS image analysis and additionally protects Linux fallback entry for `.iso`.
It also applies to Windows fallback entry for `.iso`.

## Global Image Analysis Timeout

For `.dmg`, `.iso`, and `.cdr` sources:

- the full image-analysis session is guarded by a global 20-second timeout,
- if recognition does not complete within 20 seconds, analysis is force-finished as unrecognized (`Nie rozpoznano instalatora`),
- when timeout is hit, app must force-detach the mounted source image used for analysis (if present),
- timeout finish keeps existing UI behavior (no new messages/views), and blocks supported-flow routing as for other unrecognized outcomes,
- delayed callbacks from expired analysis sessions must be ignored and must not overwrite state after timeout.

Global app-termination cleanup invariant for ISO analysis:

- when analysis touches `.iso` source, app registers source-image path for centralized exit cleanup,
- on app termination, centralized cleanup force-detaches tracked Linux/Windows source-image entities (by `image-path` match from `hdiutil info -plist`),
- this termination cleanup runs even if user exits during analysis before workflow start.

Raw Linux `.img` force path registers the selected source as a Linux image for centralized termination cleanup, but it does not mount or inspect the source image during analysis.

For Linux fallback on `.iso`:

- cleanup scope includes all image entities captured from `hdiutil info -plist` for the selected `image-path`,
- cleanup is not limited to one mount-point; it must include all captured `dev-entry` and fallback `mount-point` detach attempts,
- Linux entity cleanup must run on Linux success, Linux failure, timeout, cancel, and reset paths.

## USB Unreadable Target Hint (Non-blocking)

During analysis screen USB target area:
- if a physical external USB disk is connected but unreadable for macOS mount stack, show a warning hint with Disk Utility guidance,
- this hint does not replace supported-target validation (capacity/APFS) for readable drives,
- generic `Nie wykryto nośnika USB` message is suppressed when unreadable USB hint is active and picker has no readable targets,
- Disk Utility action inside this hint remains interactive regardless of analysis-state gating for USB selection controls.
- this hint is shown only for macOS-target flow; Linux-target flow suppresses this hint and uses physical `diskX` selection.
- in macOS flow, this hint is shown only after macOS routing is detected (it stays hidden before system detection).

## Manual Source Checksum Action

After a successful analysis result for a selected source file, the analysis success area exposes a manual SHA-256 checksum action for supported non-`.app` source formats.
This action is optional and user-triggered only; it must not run during automatic analysis and must not affect compatibility flags, USB target validation, workflow routing, downloader behavior, helper behavior, or USB creation.

Checksum calculation:

- is available for successful `.dmg`, `.iso`, `.cdr`, and raw Linux `.img` recognition, including manually forced Linux `.iso` selection and raw Linux `.img` selection,
- stays hidden for `.app` sources, unsupported results, unrecognized results, and active analysis,
- presents the checksum sheet only when the selected source URL is already bound, so the 420 px-wide sheet opens and starts calculation immediately while keeping a 240 px minimum height and allowing taller content,
- reads the source file in one pass with POSIX file I/O and a fixed 4 MiB buffer,
- runs in the app process as a background utility task,
- supports progress, cancellation, and cancellation on sheet dismissal.

## Logging and Diagnostics

Analysis should log:
- selected source type,
- detected compatibility family/flags,
- macOS prerelease classification signals and decision,
- explicit block reasons (for example mounted image conflict),
- image-analysis timeout start/finish events for `.dmg`/`.iso`/`.cdr`,
- timeout-triggered image detach result (success/failure + mount path),
- ignored stale callbacks when an expired image-analysis session returns results after timeout.

Manual source checksum action should additionally log:

- checksum start with selected source path and file size,
- POSIX cache policy result when `F_NOCACHE` is attempted,
- percentage progress at 25% bounded intervals,
- cancellation, failure, and final SHA-256 result.

Linux fallback should additionally log:

- fallback transition from macOS detection to Linux detection,
- fallback transition from mounted detection to `bsdtar` detection when needed,
- parsed Linux details (`distro`, `version`, `edition`, `arch`, `isARM`),
- Linux gate signals and classification source fields (`rule`, `matched_signal`, `version_source`),
- evidence summary used for recognition,
- Linux attach-session snapshot plus per-entity cleanup result and residual summary,
- archive-reader diagnostics relevant to bounded execution (`bsdtar` timeout/errors),
- install handoff readiness (`linuxSourceURL` present, capacity computed).
- manual-force diagnostics when Linux is forced from menu.
- raw `.img` force diagnostics when Linux is forced from the Tools menu.

Windows fallback should additionally log:

- fallback transition from macOS detection to Windows detection,
- parsed Windows details (`family`, `service_pack`, `arch`, `isARM`),
- support gate decision (`is_supported`, `support_reason`, `has_efi`),
- detected and eligible BIOS/UEFI modes after family/architecture qualification,
- present and missing required marker evidence for both boot modes,
- evidence summary used for recognition.

## Update Trigger

Update when detection heuristics, compatibility mapping, or blocking/handoff logic changes.
