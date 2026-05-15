# Linux Analysis Flow and Rules

This document defines Linux-source detection behavior in `SystemAnalysisView` analysis stage.

## Scope

Linux detection is a fallback path in analysis, with install handoff enabled.

- Primary path remains macOS installer detection.
- Linux path runs when macOS installer metadata is not detected from `.iso` source.
- Linux path can also be forced manually from `Opcje -> Pomiń analizowanie pliku -> Linux` after unsupported/unrecognized analysis, but only when selected source is `.iso`.
- Positive Linux detection unlocks USB selection and installer creation flow.

## Trigger and Entry

Linux fallback is entered when all conditions are met:

- selected source is `.iso`,
- source is not blocked by pre-mounted image guard,
- macOS installer `.app` metadata was not resolved.

Runtime sequence:

- app first attempts standard image attach/read path (same as macOS analysis),
- for `.iso`, mount-and-read step has a Linux soft-timeout of `10 s`; after timeout, flow skips mount result and continues Linux fallback,
- when macOS installer is not found, Linux detection first tries mounted-image metadata if mount path exists,
- if mounted-image Linux detection does not produce a result (or mount path is unavailable), app falls back to archive reading via `bsdtar` (without mounting).
- the whole `.iso` image-analysis session is additionally guarded by a global 20-second timeout; on timeout, analysis is force-finished as unrecognized installer.
- on timeout, any mounted source image for this analysis session must be force-detached before finalizing state.

If `.iso` is already mounted manually in macOS, Linux fallback entry is blocked and user must unmount first (guard shared with macOS image-analysis path).

## Detection Inputs (Performance Policy)

Detection uses a bounded whitelist of files only.
No recursive unpacking of live rootfs/squashfs is allowed.

- `.disk/info`
- `.treeinfo`
- `install/.treeinfo`
- `dists/*/Release` (first matching release file)
- `arch/version`
- `version.txt` (for NixOS short version extraction)
- `README.txt` (bounded hint scan for additional distro confidence, including Gentoo)
- boot/menu config snippets:
  - `boot/grub/grub.cfg`
  - `boot/grub/loopback.cfg`
  - `boot/grub2/grub.cfg`
  - `EFI/BOOT/grub.cfg`
  - `boot/grub/kernels.cfg`
  - `boot/syslinux/syslinux.cfg`
  - `boot/x86_64/loader/isolinux.cfg`
- top-level directory names from mounted root
- Linux mount-session snapshot from `hdiutil info -plist` (image-path scoped, all entities)

For `bsdtar` fallback:

- archive index is read with `bsdtar -tf`,
- selected text files are read with `bsdtar -xOf`,
- both operations are time-bounded (10 seconds timeout),
- file reads are size-bounded (max bytes cap) to avoid UI stalls.

## Classification Rules

Detection result must produce:

- distro name (if recognized),
- version (if recognized),
- edition/flavor (if available),
- architecture and ARM flag,
- evidence list for logs.

Classification uses two layers:

- dedicated high-confidence rules for popular distros (for example Ubuntu/Xubuntu, Debian, Kali, Arch, Manjaro, openSUSE, Fedora),
- catalog-based signal matching for additional distros available in icon resources (based on bounded metadata fields, without recursive filesystem scans).

Dedicated Linux rules include:

- `NixOS` with short version from `version.txt` (for example `25.11`),
- `Garuda` via `garuda` / `misobasedir=garuda` / `.miso` signals,
- `Gentoo` with additional confidence from `grub.cfg` / `README.txt` hints.

If Linux signals are present but distro cannot be matched, result is still Linux and displayed as unknown distro.

## UI Output and Gating

Display format:

- recognized distro: `Linux - <Distro> <Version>`
- unknown distro: `Linux - nierozpoznana dystrybucja`
- if ARM detected: append ` (ARM)`

Linux recognition is shown as successful detection in analysis UI and enables install handoff:

- `linuxSourceURL` is assigned,
- USB selection switches to physical external USB whole-disk targets (`diskX`),
- Linux picker includes physical USB media regardless of mountable volume presence,
- Linux picker labels use `diskX - <size> - <USB standard>` (no extra suffixes),
- non-removable external USB disks stay gated by existing `AllowExternalDrives` preference,
- proceed is available after Linux capacity validation (APFS does not block Linux flow),
- unreadable-USB warning card from macOS flow is hidden in Linux flow,
- installation workflow starts from shared summary/progress/finish UI,
- Linux helper branch uses raw copy (`dd`) stages.

Manual Linux force from menu sets Linux workflow state without distro recognition:

- display name: `Linux`,
- distro metadata: unresolved (no distro/version/edition),
- icon: generic Linux fallback (`linux.icns`),
- source handoff: selected file path is used as `linuxSourceURL`.
- manual force is available only when selected source extension is `.iso`; for other extensions request is ignored and Linux state is not applied.

Required USB capacity is computed from source file size:

- source size `<= 6_000_000_000` bytes -> `8 GB`,
- source size `> 6_000_000_000` and `<= 14_000_000_000` bytes -> `16 GB`,
- source size `> 14_000_000_000` bytes -> `32 GB`.

If source size cannot be resolved from file metadata, fallback capacity is `16 GB`.

Linux detected state uses icon fallback chain:

- first: distro-specific icon from `macUSB/Resources/Icons/Linux/Distros/*.png` when distro is recognized and mapped,
  runtime lookup supports both `Icons/Linux/Distros` and bundled `Distros` subdirectory variants,
- second: generic Linux icon `macUSB/Resources/Icons/Linux/linux.icns` (lookup: `Icons/Linux` subdirectory, then bundle root),
- third: SF Symbol fallback in UI when no file icon could be loaded.

## Logging Contract

When Linux fallback runs, logs must include:

- transition entry from macOS detection to Linux fallback,
- transition entry from mounted Linux detection to archive (`bsdtar`) fallback when needed,
- image-analysis timeout session diagnostics (`runID`, timeout start, timeout finish when triggered),
- timeout-triggered source-image detach diagnostics (mount path + success/failure),
- final Linux result string,
- Linux gate signal list (`gate_signals`),
- classification summary (`rule`, `matched_signal`, `version_source`),
- parsed details: `distro`, `version`, `edition`, `arch`, `isARM`,
- source file size in bytes (when available),
- selected USB threshold in GB only,
- evidence summary (files/rules that produced the result),
- mount-session snapshot (`entities_count`, `dev_entries`, `mount_points`) when available,
- cleanup result per entity (`detach_ok`/`detach_fail`),
- cleanup summary (`all_detached`, `residual_entities_count`),
- archive-reader diagnostics for timeout/error cases,
- ignored stale callback entry when an expired session returns after timeout.

When manual Linux force runs, logs must include:

- manual-force transition entry,
- selected source path,
- resolved source file size in bytes (when available),
- selected USB threshold in GB only.
- explicit fallback log when source size is unavailable.

## Reset and Lifecycle Rules

Linux analysis state must be reset on:

- new file selection/drop,
- full analysis reset,
- explicit transitions that force another workflow family (for example Tiger manual selection).

Mount lifecycle behavior remains aligned with existing analysis behavior:

- previous attached image is detached before analyzing another source,
- attached image path is stored for deterministic cleanup.
- Linux fallback additionally captures full image session entities (`dev-entry` + `mount-point`) for `.iso`.
- Linux cleanup runs on success/failure/timeout/cancel/reset.
- Linux cleanup order:
  - first: `hdiutil detach -force` for all captured `dev-entry`,
  - second: fallback `hdiutil detach -force` for all captured `mount-point`,
  - then residual check for the same `image-path`.

## Non-goals

- No Linux distro-specific installer customization.
- No persistent storage configuration for Linux media.
- No distro icon extraction from ISO.

## Update Trigger

Update this file when Linux detection heuristics, fallback routing, display format, or install-gating rules change.
