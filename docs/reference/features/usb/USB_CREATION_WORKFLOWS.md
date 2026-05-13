# USB Creation Workflows Contract

## Core Rule

Start path is destructive and must require explicit confirmation.
Workflow selection must respect analyzed compatibility flags.

## Workflow Families

- Standard `createinstallmedia` path
- Legacy restore-style path
- Mavericks restore path
- PPC dedicated formatting/restore path
- Catalina and Sierra dedicated handling where required
- Linux raw-copy path (`dd`)
- Windows ISO copy path (FAT32/MBR + optional WIM split)

Linux raw-copy stages:
- `linux_unmount_target` — target USB unmount (indeterminate stage),
- `linux_raw_copy` — raw image copy to whole disk (`/dev/rdiskX`) with progress + write speed,
- `linux_verify_write` — post-write verification by comparing SHA-256 of source image with SHA-256 of first `N` bytes on target raw disk (`N = source image size`) (indeterminate stage),
- `cleanup_temp` — deterministic temp cleanup,
- `finalize` — terminal state transition.

Windows workflow stages:
- `windows_prepare_source` — source ISO validation, hidden mount, FAT32-limit scan, WIM split decision (indeterminate stage),
- `windows_prepare_target` — target USB unmount with retry/force prompt path and FAT32/MBR formatting (indeterminate stage),
- `windows_create_media` — ISO file copy to USB (`rsync`) with determinate progress + write speed,
- `windows_split_wim` — conditional `install.wim` split via `wimlib-imagex` with determinate progress + write speed (stage appears only when needed),
- `windows_verify_media` — boot file and structure validation (`boot.wim`, UEFI markers, `install.wim`/`install.swm`) (indeterminate stage),
- `windows_cleanup_temp` — deterministic cleanup of temp files and helper-managed hidden image mount,
- `finalize` — terminal state transition.

Linux auto-mount guard invariant:
- for Linux workflow, helper blocks system auto-mount for target whole-disk (`diskX` and `diskXsY`) from start of `linux_unmount_target` until `linux_verify_write` ends,
- guard is always released right after `linux_verify_write` terminal outcome (`success`, `failure`, `cancel`),
- if workflow fails before `linux_verify_write`, guard is released in terminal failure cleanup path.

Linux summary screen (`UniversalInstallationView`) should show an informational card before the process-stages section:
- card is visible only for Linux workflow,
- card uses accent tone (`.active`) with SF Symbol `info.circle.fill`,
- copy explains that macOS may show an unreadable-disk dialog and user should choose `Ignore`.

Windows summary screen (`UniversalInstallationView`) should show an informational card before the process-stages section:
- card is visible only for Windows workflow,
- card uses accent tone (`.active`) with SF Symbol `info.circle.fill`,
- copy clearly states that prepared media is UEFI-only and that Legacy BIOS boot is not supported.

Windows summary pre-start prerequisites:
- if Windows workflow requires `install.wim` split and `wimlib-imagex` is not detected, start action is blocked before workflow start.
- in blocked state, summary keeps a divider with warning label and replaces process/time cards with an orange prerequisites card.
- prerequisites card includes:
  - required `wimlib` message,
  - split-specific context,
  - Homebrew-guided path (with Homebrew website action only when Homebrew is not detected),
  - refresh action to re-probe `brew`/`wimlib-imagex`.
- when refresh detects `wimlib-imagex`, start unblocks immediately and standard process/time cards are restored.

## Helper and Privilege Invariants

- Privileged operations must run through helper (`SMAppService + XPC`).
- No terminal fallback privileged execution path.
- Stage progression shown in UI must remain deterministic.
- Linux raw-copy must target whole-disk device, never a partition node.
- Windows workflow must copy installer files 1:1 from ISO payload (no UEFI fallback file synthesis).
- Windows target format must be `MS-DOS (FAT32)` + `MBR`.

## Power Management Invariant

- Idle sleep is blocked for the full USB creation runtime.
- Sleep blocker is activated at creation process start.
- Sleep blocker is released on every terminal path: success, failure, and cancellation.

## Logging and Diagnostics

Creation workflow logs should include:
- branch selection reason,
- stage transitions,
- helper progress mapping,
- cancellation/failure shaping,
- critical command outcomes used for diagnosis.

Linux workflow logs should additionally include:
- source image path and size,
- resolved target whole-disk identifier,
- raw-copy progress and speed metrics,
- verification summary (source hash preview vs target hash preview, compared byte count, pass/fail),
- terminal result (`success/fail/cancel`) and failed stage when present.

## Update Trigger

Update when stage sequencing, branching, or helper interaction semantics change.
