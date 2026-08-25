# User Flow and Navigation

## Main Flow Contract

The primary flow remains:
- `WelcomeView -> SystemAnalysisView -> UniversalInstallationView -> CreationProgressView -> FinishUSBView`

Destructive start requires explicit confirmation.

## Current Runtime Behavior

- User selects source and runs analysis.
- Analysis resolves compatibility flags and workflow branch.
- For macOS installers, analysis also compares the physical Mac architecture with `createinstallmedia`; Intel hosts reject ARM-only tools and unreadable architectures fail closed.
- User selects target USB and confirms destructive start.
- Progress screen reflects helper-driven stages.
- Finish screen reports success/failure/cancel plus cleanup status.
- Language changes are available on Welcome and on the analysis screen before analysis begins. Starting analysis, forcing an analysis result, or opening the downloader locks language changes until the flow returns to Welcome.
- Any active protected operation also disables language changes, including startup helper repair, cleanup, and USB ejection.
- `Command-Q` and main-window close use the same termination guard. Active work blocks exit with one warning; an idle app performs termination cleanup and exits.

Apple Silicon and Rosetta behavior:

- Yosemite through Catalina installers with Intel-only `createinstallmedia` continue to the summary with a Rosetta requirement,
- missing or indeterminate Rosetta availability blocks `Start`, while installer analysis itself remains successful,
- the summary requires explicit acceptance of Apple software license terms before the privileged helper runs the fixed Rosetta installation command,
- while installation or availability checking is active, both `Start` and `Back` are disabled,
- successful installation is followed by at most five availability probes; unresolved and failed outcomes remain blocked and expose a localized retry action.

Linux-specific runtime behavior:
- recognized Linux image (`.iso`) unlocks the same shared install flow,
- `Tools -> Write a Raw Image to a Drive...` accepts `.iso` and `.img` from Welcome or an empty analysis screen after a warning and dedicated picker,
- manual raw-image selection skips content analysis and source mounting, displays the selected filename with neutral image wording, and enters the existing Linux raw-copy flow through app-only presentation state,
- USB validation keeps capacity gating, while APFS blocking is macOS-only (Linux uses physical `diskX` targets),
- creation branch uses unchanged Linux raw-copy helper stages and hides Linux-specific post-write guidance for manual raw images.

Windows-specific runtime behavior:

- analysis recognizes supported Windows families from original `.iso` images and resolves eligible BIOS/UEFI modes from bounded boot-marker evidence,
- the summary presents the family-appropriate boot-mode state; dual-mode images default to UEFI and retain the user's session-only selection,
- the selected mode is sent to the helper as required `windowsBootMode`,
- BIOS selection validates helper capability `windows.macusboot.v1` before destructive confirmation; persistent capability failure blocks start with helper-repair guidance,
- BIOS execution appends the non-cancellable `windows_install_macusboot` transaction after media verification and before cleanup, while UEFI never loads or writes the macUSBoot artifact,
- if a cancellation request races with entry into macUSBoot, helper rejection keeps the progress flow active and must not produce a cancelled finish result.

## Tools Flow: Downloader

- `Tools -> Download macOS installer...` opens downloader window.
- The downloader window owns an active-operation token from presentation until the window is fully closed, including discovery, list, process, and summary states.
- `Tools -> Write a Raw Image to a Drive...` is placed under the downloader action, separated by a divider, and is enabled only on Welcome or on `SystemAnalysisView` before any source file is selected.
- `SystemAnalysisView` also exposes `Pobierz` between `Wybierz` and `Analizuj` for direct downloader access.
- Downloader opening is blocked during USB creation operation stages (`UniversalInstallationView`, `CreationProgressView`, `FinishUSBView`), and `Tools -> Pobierz instalator macOS...` is disabled there.
- Discovery starts on entering downloader window (never on app startup).
- Downloader also passively checks Full Disk Access and helper XPC readiness on entry and app activation. Missing prerequisites do not block discovery or selection, but they surface an orange warning action and block `Download` before any session begins.
- Selecting the prerequisite warning or attempting a blocked download presents an actionable app-icon alert. Returning from System Settings refreshes the state without rerunning discovery or clearing selection.
- While discovery runs, header/options remain visible; list area shows scanning panel.
- After discovery completes, grouped systems list is shown.
- On downloader summary, when final `.app` exists, icon action can pass installer path to analysis and trigger automatic analysis; from Welcome, app navigates to analysis first.

## Update Trigger

Update when flow order, transitions, or gate behavior changes.
