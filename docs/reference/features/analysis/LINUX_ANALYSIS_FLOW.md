# Linux Analysis Flow and Rules

This document defines Linux-source detection behavior in `SystemAnalysisView` analysis stage.

## Scope

Linux detection is a fallback path in analysis, with install handoff enabled.

- Primary path remains macOS installer detection.
- Linux path runs when macOS installer metadata is not detected from `.iso` / `.cdr` sources.
- Positive Linux detection unlocks USB selection and installer creation flow.

## Trigger and Entry

Linux fallback is entered when all conditions are met:

- selected source is `.iso` or `.cdr`,
- source is not blocked by pre-mounted image guard,
- macOS installer `.app` metadata was not resolved.

Runtime sequence:

- app first attempts standard image attach/read path (same as macOS analysis),
- when macOS installer is not found, Linux detection first tries mounted-image metadata if mount path exists,
- if mounted-image Linux detection does not produce a result (or mount path is unavailable), app falls back to archive reading via `bsdtar` (without mounting).

If `.iso`/`.cdr` is already mounted manually in macOS, analysis is blocked and user must unmount first (same guard as macOS analysis path).

## Detection Inputs (Performance Policy)

Detection uses a bounded whitelist of files only.
No recursive unpacking of live rootfs/squashfs is allowed.

- `.disk/info`
- `.treeinfo`
- `install/.treeinfo`
- `dists/*/Release` (first matching release file)
- `arch/version`
- boot/menu config snippets:
  - `boot/grub/grub.cfg`
  - `boot/grub/loopback.cfg`
  - `boot/grub2/grub.cfg`
  - `EFI/BOOT/grub.cfg`
  - `boot/grub/kernels.cfg`
  - `boot/syslinux/syslinux.cfg`
  - `boot/x86_64/loader/isolinux.cfg`
- top-level directory names from mounted root

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

If Linux signals are present but distro cannot be matched, result is still Linux and displayed as unknown distro.

## UI Output and Gating

Display format:

- recognized distro: `Linux - <Distro> <Version>`
- unknown distro: `Linux - nierozpoznana dystrybucja`
- if ARM detected: append ` (ARM)`

Linux recognition is shown as successful detection in analysis UI and enables install handoff:

- `linuxSourceURL` is assigned,
- USB selection/proceed is available after capacity/APFS validation,
- installation workflow starts from shared summary/progress/finish UI,
- Linux helper branch uses raw copy (`dd`) stages.

Required USB capacity is computed from source file size:

- source size `<= 6_000_000_000` bytes -> `8 GB`,
- source size `> 6_000_000_000` and `<= 14_000_000_000` bytes -> `16 GB`,
- source size `> 14_000_000_000` bytes -> `32 GB`.

Linux detected state uses icon fallback chain:

- first: distro-specific icon from `macUSB/Resources/Icons/Linux/Distros/*.png` when distro is recognized and mapped,
  runtime lookup supports both `Icons/Linux/Distros` and bundled `Distros` subdirectory variants,
- second: generic Linux icon `macUSB/Resources/Icons/Linux/linux.icns` (lookup: `Icons/Linux` subdirectory, then bundle root),
- third: SF Symbol fallback in UI when no file icon could be loaded.

## Logging Contract

When Linux fallback runs, logs must include:

- transition entry from macOS detection to Linux fallback,
- transition entry from mounted Linux detection to archive (`bsdtar`) fallback when needed,
- final Linux result string,
- parsed details: `distro`, `version`, `edition`, `arch`, `isARM`,
- source file size in bytes (when available),
- selected USB threshold in GB only,
- evidence summary (files/rules that produced the result),
- archive-reader diagnostics for timeout/error cases.

## Reset and Lifecycle Rules

Linux analysis state must be reset on:

- new file selection/drop,
- full analysis reset,
- explicit transitions that force macOS-only state (for example Tiger manual selection).

Mount lifecycle behavior remains aligned with existing analysis behavior:

- previous attached image is detached before analyzing another source,
- attached image path is stored for deterministic cleanup.

## Non-goals

- No Linux distro-specific installer customization.
- No persistent storage configuration for Linux media.
- No distro icon extraction from ISO.

## Update Trigger

Update this file when Linux detection heuristics, fallback routing, display format, or install-gating rules change.
