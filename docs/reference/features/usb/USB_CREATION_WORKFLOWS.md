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
- Linux raw-copy path (`dd`) for recognized `.iso` sources and exceptional forced raw `.img` sources
- Windows ISO copy path (FAT32/MBR + optional WIM split), with a conditional macUSBoot final write for BIOS media

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
- `windows_create_autounattend` — conditional `Autounattend.xml` generation and XML validation (indeterminate stage; appears only when macUSB generates its own file),
- `windows_verify_media` — boot-mode-aware boot file and structure validation (`boot.wim`, BIOS or UEFI markers, `install.wim`/`install.swm`) (indeterminate stage),
- `windows_install_macusboot` — BIOS-only, non-cancellable macUSBoot artifact/layout/write/readback transaction after media verification and before cleanup (indeterminate stage),
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

Windows summary screen (`UniversalInstallationView`) shows boot-mode information before the process-stages section:
- all variants use an accent card (`.active`) with SF Symbol `info.circle.fill`,
- `Vista`, `7`, and `Server 2008 R2` show a BIOS-only informational card,
- `8` through `10` and `Server 2012` through `Server 2022` show a segmented BIOS/UEFI control driven by analyzed eligible modes,
- dual-mode selection defaults to UEFI; a single eligible mode remains selected in a disabled control,
- `11` and `Server 2025` retain the UEFI-only informational card,
- the selected mode is session-only, logged, and included in the helper request as required `windowsBootMode` for Windows workflows,
- BIOS summary states that macUSBoot will be installed and includes the conditional stage in progress UI; UEFI does not show or execute that stage.

Windows source trust boundary:

- the tested creation contract covers original Microsoft Windows ISO images,
- modified or repacked images are outside the tested compatibility scope,
- structural analysis and boot-marker verification do not certify image provenance; selecting an appropriate, independently verified ISO remains the user's responsibility.

Windows automatic configuration card:
- card is visible only for recognized desktop Windows 10 64-bit and Windows 11 images; Windows 10 32-bit, Windows 10 ARM, and Windows Server do not show this card,
- when the card appears together with the configurable BIOS/UEFI selector, the generic process-duration card is omitted to keep the fixed-height summary within the visible area,
- state is session-only and keyed to the selected ISO path plus file identity when available,
- Windows 10 64-bit and Windows 11 offer automatic BitLocker device-encryption prevention, privacy data-collection opt-out, Wi-Fi/network setup skip, Microsoft-account requirement bypass, local-account options, and language/region transfer from the current Mac,
- only Windows 11 offers the combined TPM 2.0/Secure Boot/RAM hardware-bypass option,
- language/region transfer reads the current macOS preferred language and locale, verifies the language against `sources/lang.ini` immediately after a supported automatic-configuration image is detected, uses the language tag as Windows `InputLocale` so Windows picks its default keyboard for that language, and is shown disabled when the ISO language cannot be verified,
- local-account creation accepts a Windows display name in the UI; the final display name must be non-empty, max 256 characters, not `NONE`, and contain only letters, digits, and spaces; when the field contains an invalid character, the options sheet shows an orange validation message, and the `Done` action and workflow start stay blocked; app side derives a separate local account `Name` from it using only ASCII letters and digits, max 20 characters, with a deterministic ASCII fallback when the display name contains no usable characters,
- Wi-Fi/network setup skip automatically enables Microsoft-account requirement bypass and locks that option while selected,
- automatic local-account creation is available only after Microsoft-account requirement bypass is selected,
- if the mounted source already contains a root-level `Autounattend.xml` or `sources/$OEM$/$$/Panther/unattend.xml` with any casing and automatic configuration is enabled, app-side pre-start flow must show a warning alert before destructive confirmation,
- choosing the source file sends no autounattend payload and hides `windows_create_autounattend`,
- choosing the macUSB file sends the autounattend payload and helper writes the answer file after media copy and optional WIM split, before media verification.

Windows summary pre-start prerequisites:
- BIOS selection queries helper capability `windows.macusboot.v1` before destructive confirmation; the helper exposes it only when the bundled macUSBoot artifact resolves and validates successfully. App version/build fingerprint changes re-register updated helper builds. A missing artifact or stale/incompatible helper is reloaded once and queried again, then start remains blocked with the existing helper-repair guidance if capability validation still fails.
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
- Every Windows helper request must contain `windowsBootMode`; a missing mode is rejected before stage execution.
- Linux raw-copy must target whole-disk device, never a partition node.
- Windows workflow must copy installer files 1:1 from ISO payload (no UEFI fallback file synthesis).
- Windows BIOS source and target verification require case-insensitive `BOOTMGR`, `boot/BCD`, and `sources/boot.wim`. UEFI verification retains the EFI-directory plus accepted EFI-loader-marker contract and also requires `sources/boot.wim` on target media.
- `windows_install_macusboot` is appended only for BIOS after `windows_verify_media` and before `windows_cleanup_temp`; the UEFI stage graph and media contents remain unchanged.
- macUSBoot accepts only the pinned, exact three-file bundled resource set and the supported 512-byte logical-sector MBR layout. It writes StageTwo first, synchronizes and fully reads it back, then writes the MBR boot-code bytes while preserving the target partition table/signature bytes, synchronizes and reads back again, and finally verifies the protected range.
- macUSBoot has no retry, rollback, or checkpoint. Cancellation is disabled and helper cancellation requests are ignored while this stage is active. The app rechecks this gate before dispatch and remains in the active workflow when the helper rejects a racing cancellation request; it must not present a cancelled result. The Disk Arbitration guard and raw descriptor are released on every terminal path, followed by exactly one whole-disk mount attempt.
- Windows automatic configuration may add or replace only the Windows answer-file location selected by the generated passes, when explicitly enabled by the user. If the generated XML contains `windowsPE`, helper writes root-level `Autounattend.xml`; otherwise it writes `sources/$OEM$/$$/Panther/unattend.xml` so Windows Setup copies it to `%WINDIR%/Panther/unattend.xml` for later passes. The `windowsPE` pass is generated for options that require Windows PE setup data, such as the Windows 11 hardware-requirements bypass. Windows 10 64-bit automatic configuration does not generate the TPM 2.0/Secure Boot/RAM bypass. When automatic BitLocker device-encryption prevention is enabled, macUSB writes a `specialize` pass command that sets `HKLM\SYSTEM\CurrentControlSet\Control\BitLocker\PreventDeviceEncryption` to `1`.
- Windows automatic configuration may set `Microsoft-Windows-International-Core` language, input, system locale, and user locale values in `oobeSystem` when Mac language/region transfer is enabled.
- Windows automatic configuration may set `OOBE/ProtectYourPC` to `3` when privacy data-collection opt-out is enabled.
- Windows automatic configuration may set `OOBE/HideWirelessSetupInOOBE` to `true` when Wi-Fi/network setup skip is enabled.
- Windows automatic local-account creation writes both `Name` and `DisplayName` for `Microsoft-Windows-Shell-Setup/UserAccounts/LocalAccounts/LocalAccount`; `DisplayName` preserves the user-entered display name, while `Name` is generated without spaces or special characters and limited to 20 ASCII letters/digits.
- Windows target format must be `MS-DOS (FAT32)` + `MBR`.
- Windows target volume labels are selected from the detected family:
  - desktop: `WINXP-MU`, `WINVS-MU`, `WIN7-MU`, `WIN8-MU`, `WIN81-MU`, `WIN10-MU`, or `WIN11-MU`,
  - server: `SRV03-MU`, `SRV08-MU`, `SRV12-MU`, `SRV16-MU`, `SRV19-MU`, `SRV22-MU`, or `SRV25-MU`,
  - Server 2012 and Server 2012 R2 share `SRV12-MU`,
  - XP and Server 2003 labels are reserved for future workflow support; both families remain unsupported by the current support gate.

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

Windows summary logs additionally include boot-mode initialization, user selection changes, helper capability preflight/reload outcomes, and the boot mode sent in the request.

Windows macUSBoot helper logs additionally include:
- semantic phase transitions and artifact identity/hash validation,
- full logical `diskutil` commands with safe arguments, exit status, and bounded output,
- raw-device open/close, logical sector geometry, layout checks, write/sync/readback phases, and final protected-range verification,
- Disk Arbitration guard lifecycle and the single final mount result,
- no binary payload contents.

Linux workflow logs should additionally include:
- source image path and size,
- resolved target whole-disk identifier,
- raw-copy progress and speed metrics,
- verification summary (source hash preview vs target hash preview, compared byte count, pass/fail),
- terminal result (`success/fail/cancel`) and failed stage when present.

## Update Trigger

Update when stage sequencing, branching, or helper interaction semantics change.
