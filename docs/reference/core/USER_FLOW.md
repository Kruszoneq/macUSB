# User Flow and Navigation

## Main Flow Contract

The primary flow remains:
- `WelcomeView -> SystemAnalysisView -> UniversalInstallationView -> CreationProgressView -> FinishUSBView`

Destructive start requires explicit confirmation.

## Current Runtime Behavior

- User selects source and runs analysis.
- Analysis resolves compatibility flags and workflow branch.
- User selects target USB and confirms destructive start.
- Progress screen reflects helper-driven stages.
- Finish screen reports success/failure/cancel plus cleanup status.

Linux-specific runtime behavior:
- recognized Linux image (`.iso`) unlocks the same shared install flow,
- `Tools -> Write Raw Linux Image (.img)...` can force a selected `.img` file into Linux raw-copy flow from Welcome or an empty analysis screen after a warning and dedicated `.img` picker,
- USB validation keeps capacity gating, while APFS blocking is macOS-only (Linux uses physical `diskX` targets),
- creation branch uses Linux raw-copy helper stages.

Windows-specific runtime behavior:

- analysis recognizes supported Windows families from original `.iso` images and resolves eligible BIOS/UEFI modes from bounded boot-marker evidence,
- the summary presents the family-appropriate boot-mode state; dual-mode images default to UEFI and retain the user's session-only selection,
- the selected mode is sent to the helper as required `windowsBootMode`,
- BIOS selection validates helper capability `windows.macusboot.v1` before destructive confirmation; persistent capability failure blocks start with helper-repair guidance,
- BIOS execution appends the non-cancellable `windows_install_macusboot` transaction after media verification and before cleanup, while UEFI never loads or writes the macUSBoot artifact,
- if a cancellation request races with entry into macUSBoot, helper rejection keeps the progress flow active and must not produce a cancelled finish result.

## Tools Flow: Downloader

- `Tools -> Download macOS installer...` opens downloader window.
- `Tools -> Write Raw Linux Image (.img)...` is placed under the downloader action, separated by a divider, and is enabled only on Welcome or on `SystemAnalysisView` before any source file is selected.
- `SystemAnalysisView` also exposes `Pobierz` between `Wybierz` and `Analizuj` for direct downloader access.
- Downloader opening is blocked during USB creation operation stages (`UniversalInstallationView`, `CreationProgressView`, `FinishUSBView`), and `Tools -> Pobierz instalator macOS...` is disabled there.
- Discovery starts on entering downloader window (never on app startup).
- While discovery runs, header/options remain visible; list area shows scanning panel.
- After discovery completes, grouped systems list is shown.
- On downloader summary, when final `.app` exists, icon action can pass installer path to analysis and trigger automatic analysis; from Welcome, app navigates to analysis first.

## Update Trigger

Update when flow order, transitions, or gate behavior changes.
