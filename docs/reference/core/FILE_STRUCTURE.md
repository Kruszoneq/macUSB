# File Structure Reference

## Core docs

- `docs/AGENTS.md` — process rules for agents.
- `docs/reference/README.md` — runtime documentation map.
- `docs/CHANGELOG.md` — release notes.

## Runtime areas

- `macUSB/Features/Analysis/*` — source analysis and compatibility routing.
- `macUSB/Features/Installation/*` — USB creation summary/start/progress orchestration.
- `macUSB/Features/Finish/*` — result and cleanup UX.
- `macUSB/Features/Downloader/*` — downloader coordinator + UI + logic split.

### Welcome layout

- `macUSB/Features/Welcome/WelcomeView.swift` — welcome UI, manual and optional automatic analysis navigation.
- `macUSB/Features/Welcome/WelcomeAutoSkipPreferences.swift` — NSAlert confirmation before persisting the automatic welcome-skip preference.
- `macUSB/Features/Welcome/WelcomeStartupCoordinator.swift` — session-owned startup orchestration, prerequisite gating, and one-shot automatic navigation.
- `macUSB/Features/Welcome/WelcomeStartupUpdateChecker.swift` — startup update request, metadata validation, existing update alert, and explicit up-to-date/update-available/failure result.

### Analysis layout

- `macUSB/Features/Analysis/SystemAnalysisView.swift` — analysis UI screen and navigation/lifecycle wiring.
- `macUSB/Features/Analysis/SystemAnalysisUSBSectionView.swift` — existing USB requirements, prepared picker and capacity/destructive-warning presentation.
- `macUSB/Features/Analysis/AnalysisUSBDiscoveryPresentation.swift` — error/waiting cards, actual verified-alternative hint and deliberate-selection NSAlert.
- `macUSB/Features/Analysis/AnalysisLogic.swift` — analysis state + facade API for UI bindings.
- `macUSB/Features/Analysis/AnalysisSelectionHandoff.swift` — handoff bridge for pending installer URL from downloader flow.
- `macUSB/Features/Analysis/AnalysisNotifications.swift` — shared `Notification.Name` constants used by analysis/flow wiring.
- `macUSB/Features/Analysis/Checksums/*` — manual post-analysis SHA-256 checksum action for successful non-`.app` source-file flows, including POSIX streaming service, sheet state model, and SwiftUI views.
- `macUSB/Features/Analysis/Logic/AnalysisLogicFileSelection.swift` — file selection/drop/open-panel logic.
- `macUSB/Features/Analysis/Logic/AnalysisLogicAnalysisFlow.swift` — orchestration of analysis execution for `.app` and image sources.
- `macUSB/Features/Analysis/Logic/AnalysisLogicSourceCapacityPolicy.swift` — image and `.app` source-size resolution, exact USB capacity requirement, display class, and fallback policy.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSCompatibility.swift` — macOS-only compatibility/version-family detection rules and flag mapping.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSArchitectureCompatibility.swift` — host/`createinstallmedia` architecture policy and Rosetta requirement handoff.
- `macUSB/Features/Analysis/Logic/macOS/MacOSCreateInstallMediaArchitecture.swift` — CoreFoundation-backed local executable architecture inspection and normalized Apple Silicon/Intel/universal classification.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSImageMounting.swift` — image mounting + mounted-source guard + legacy image read logic.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSInstallerMetadata.swift` — installer metadata and marketing-version parsing.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSInstallerIcon.swift` — installer icon discovery.
- `macUSB/Features/Analysis/Logic/AnalysisLogicUSBAdmission.swift` — final asynchronous read-only target identity/capacity check before handoff, without subprocesses or new prompts.
- `macUSB/Features/Analysis/Logic/AnalysisLogicUsbDrives.swift` — serialized USB refresh orchestration, snapshot/selection reconciliation and target-readiness policy.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSLifecycle.swift` — reset/cleanup/manual Tiger flow helpers.
- `macUSB/Features/Analysis/Logic/Windows/AnalysisLogicWindowsBootMarkers.swift` — bounded, case-insensitive BIOS/UEFI marker indexing for mounted Windows ISO sources.
- `macUSB/Features/Analysis/Logic/Windows/AnalysisLogicWindowsBootPolicy.swift` — Windows family/architecture policy that maps detected boot markers to eligible boot modes.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxDetection.swift` — Linux fallback entrypoint and result shaping.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxMetadata.swift` — bounded Linux metadata reads from mounted ISO/CDR.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxClassification.swift` — Linux distro/version/edition classification rules.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxArchitecture.swift` — Linux architecture normalization and ARM flag mapping.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxDisplayName.swift` — final Linux display-name formatting policy.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxLifecycle.swift` — Linux state reset/apply helpers.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxInstallationHandoff.swift` — Linux install context handoff for USB creation flow.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicRawLinuxImageLifecycle.swift` — manual `.iso`/`.img` raw-image state handoff without analysis or source mounting.
- `macUSB/Features/Analysis/RawLinuxImage/RawLinuxImageSelectionCoordinator.swift` — Tools-menu warning and dedicated raw-image picker.

### Installation layout

- `macUSB/Features/Installation/UniversalInstallationView.swift` — shared summary screen before start.
- `macUSB/Features/Installation/CreationProgressView.swift` — shared stage/progress UI.
- `macUSB/Features/Installation/CreatorLogic.swift` — shared install actions/cancel/cleanup orchestration, including app-side non-cancellable macUSBoot gating.
- `macUSB/Features/Installation/CreatorHelperLogic.swift` — shared helper workflow orchestration, authoritative cancellation-response handling, and transfer metrics.
- `macUSB/Features/Installation/macOS/CreatorMacOSRosettaLogic.swift` — summary-side Rosetta check, license confirmation, installation, and bounded post-install verification.
- `macUSB/Features/Installation/macOS/CreatorMacOSRosettaCardView.swift` — localized Rosetta status card and retry actions.
- `macUSB/Features/Installation/Linux/LinuxInstallationFlowContext.swift` — Linux flow context payload with app-only manual raw-image presentation state.
- `macUSB/Features/Installation/Linux/CreatorLinuxLogic.swift` — Linux-specific summary/cleanup helpers.
- `macUSB/Features/Installation/Linux/CreatorLinuxHelperLogic.swift` — Linux helper request construction and start routing.
- `macUSB/Features/Installation/Linux/CreationProgressLinuxMapping.swift` — Linux stage mapping and neutral manual raw-image title/status overrides for shared progress UI.
- `macUSB/Features/Installation/Windows/CreatorWindowsLabelLogic.swift` — Windows target volume-label mapping policy.
- `macUSB/Features/Installation/Windows/CreatorWindowsBootModeCardView.swift` — Windows summary BIOS/UEFI presentation, session selection, and logging.
- `macUSB/Features/Installation/Windows/CreatorWindowsHelperLogic.swift` — Windows helper request construction and workflow start routing.
- `macUSB/Features/Installation/Windows/CreatorWindowsMacUSBootPreflightLogic.swift` — BIOS-only helper capability preflight and one-shot helper reload recovery before destructive confirmation.
- `macUSB/Features/Installation/Windows/CreatorWindowsMacUSBootErrorLogic.swift` — localized macUSBoot stage-failure presentation.
- `macUSB/Features/Installation/Windows/CreatorWindowsUnmountRecoveryLogic.swift` — Windows unmount-busy prompt/retry recovery flow.
- `macUSB/Features/Installation/Windows/CreationProgressWindowsMapping.swift` — Windows stage mapping for shared progress UI.

### Shared UI layout

- `macUSB/Shared/UI/TouchBar/TouchbarSupport.swift` — global, fixed Touch Bar configuration (app branding).

### Shared platform services

- `macUSB/Shared/Services/AppActiveOperationRegistry.swift` — thread-safe token registry and diagnostic snapshots for protected runtime work.
- `macUSB/Shared/Services/AppTerminationCoordinator.swift` — shared quit and main-window close decision, blocked-exit alert, and diagnostic reporting.
- `macUSB/Shared/Services/AppTerminationCleanup.swift` — idempotent cleanup executed before allowed application exit.
- `macUSB/Shared/Services/AppWindowCloseGuard.swift` — main-window delegate forwarding close requests to the termination coordinator.
- `macUSB/Shared/Services/MacHardwareArchitecture.swift` — physical Mac architecture detection independent of the current process architecture.
- `macUSB/Shared/Services/RosettaAvailabilityProbe.swift` — execution-based Rosetta availability probe.

- `macUSB/Shared/Services/USBDiscoveryModels.swift` — structured scan outcomes, per-target verification, discovery activity and selected-target readiness.
- `macUSB/Shared/Services/USBTargetDiscoveryService.swift` — analysis-only physical USB qualification and prepared Option snapshots.
- `macUSB/Shared/Services/USBDiscoveryRegistryProbe.swift` — balanced IOKit ownership, current media identity and independent physical USB evidence.
- `macUSB/Shared/Services/USBDiscoveryVolumeCollector.swift` — current GPT/HFS+ Option-volume metadata, identity and capacity collection.
- `macUSB/Shared/Services/USBDiscoveryDiagnostics.swift` — bounded, coalesced discovery diagnostics.
- `macUSB/Shared/Services/USBDiscoveryProcessRunner.swift` — shared read-only subprocess exclusion, bounded I/O/cancellation/cleanup and query reports.
- `macUSB/Shared/Services/USBDriveRefreshPolicy.swift` — visible/active 2.5-second scheduling with duplicate-request exclusion.
- `macUSB/Shared/Services/USBDriveLogic.swift` — existing USB utilities and legacy enumeration contracts for callers outside analysis.

### Permissions layout

- `macUSB/Shared/Services/FullDiskAccessPermissionManager.swift` — Full Disk Access state orchestration, startup prompt flow, System Settings opening, and app-state publication.
- `macUSB/Shared/Services/FullDiskAccessProbe.swift` — non-destructive POSIX probes for Full Disk Access-protected files and directories.
- `macUSB/Shared/Services/FullDiskAccessTypes.swift` — internal Full Disk Access statuses, triggers, probe signals, and evaluation result types.

### Analysis docs

- `docs/reference/features/analysis/ANALYSIS_COMPATIBILITY.md` — analysis contract and routing invariants.
- `docs/reference/features/analysis/LINUX_ANALYSIS_FLOW.md` — detailed Linux fallback flow and rule set.

### Downloader layout

- `macUSB/Features/Downloader/MacOSDownloaderCoordinator.swift`
- `macUSB/Features/Downloader/Logic/MacOSDownloaderPrerequisites.swift` — combines Full Disk Access and passive helper readiness into the downloader gate while rejecting stale checks.
- `macUSB/Features/Downloader/UI/*`
- `macUSB/Features/Downloader/UI/MacOSDownloaderPrerequisiteAlerts.swift` — prerequisite alert variants and direct System Settings actions.
- `macUSB/Features/Downloader/UI/MacOSDownloaderDiskImageOptionsView.swift` — session-only DMG toggle, destination picker, abbreviated path, and change action.
- `macUSB/Features/Downloader/UI/MacOSDownloaderDiskImageAlerts.swift` — collision, destination-access, and volume-specific capacity alerts for DMG preflight.
- `macUSB/Features/Downloader/Logic/Discovery/*`
- `macUSB/Features/Downloader/Logic/Download/*`
- `macUSB/Features/Downloader/Logic/DiskImage/*` — session-only DMG output models, naming, volume-aware preflight, cancellable `hdiutil` execution, staging, rollback, and source-app removal.
- `macUSB/Features/Downloader/Logic/Assembly/*`
- `macUSB/Features/Downloader/Logic/MacOSVerificationLogic.swift`
- `macUSB/Features/Downloader/Logic/MacOSCleanupLogic.swift`

### Helper (app-side)

- `macUSB/Shared/Services/Helper/HelperIPC.swift`
- `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift`
- `macUSB/Shared/Services/Helper/PrivilegedOperationClientCapabilities.swift` — helper capability query used by BIOS preflight.
- `macUSB/Shared/Services/Helper/PrivilegedOperationClientRosetta.swift` — app-side Rosetta installation IPC wrapper.
- `macUSB/Shared/Services/Helper/PrivilegedOperationClientActivity.swift` — lifecycle tokens for long USB and downloader helper tasks.
- `macUSB/Shared/Services/Helper/HelperServiceManager.swift`
- `macUSB/Shared/Services/Helper/HelperService/*`
- `macUSB/Shared/Services/Helper/HelperService/HelperServicePassiveReadiness.swift` — passive `SMAppService` status and XPC health snapshot without recovery side effects.
- `macUSB/Shared/Services/InstallerSourceImageUnmountRegistry.swift` — centralny rejestr śledzenia zamontowanych źródeł ISO (Windows/Linux) i cleanup odmontowania przy zamknięciu aplikacji; ręczne źródła raw nie są rejestrowane.

### Helper (daemon)

- `macUSBHelper/main.swift`
- `macUSBHelper/IPC/*`
- `macUSBHelper/Service/*`
- `macUSBHelper/Service/HelperProcessLifecycle.swift` — tracks XPC connections and privileged operations so the launch-on-demand helper exits safely after normal app termination, crash, or Force Quit.
- `macUSBHelper/Workflow/*`
- `macUSBHelper/Workflow/Linux/*` — Linux raw-copy stage builder, parser, and disk ops.
- `macUSBHelper/Workflow/Windows/*` — Windows ISO-copy stage builder, exact formatted-target partition and mount-point resolution, boot-mode-aware source/target validation, progress parsing, and verification.
- `macUSBHelper/Workflow/Windows/MacUSBoot/*` — BIOS-only macUSBoot artifact validation, Disk Arbitration guard, raw-disk layout validation, transaction, disk operations, and orchestration.
- `macUSBHelper/DownloaderAssembly/*`
- `macUSBHelper/Rosetta/HelperRosettaInstaller.swift` — fixed-command, root-only Rosetta installer with bounded diagnostics.
- `macUSBHelper/Service/HelperDiagnosticLogging.swift` — shared stage and source-tag formatting for daemon system logs.

## Localization catalogs

- `macUSB/Resources/App.xcstrings` — Welcome, system menus and related app/helper messages, permission/notification prompts, update checks, startup toasts, log export, and the Tools raw-image picker, selected through `App`.
- `macUSB/Resources/Analysis.xcstrings` — all localized analysis/source/USB selection and manual checksum presentation, selected through `Analysis`.
- `macUSB/Resources/Summary.xcstrings` — complete pre-start summary, workflow-specific prerequisite/configuration cards, options sheets, Rosetta UI, and destructive confirmation, selected through `Summary`.
- `macUSB/Resources/Localizable.xcstrings` — residual shared/legacy entries and areas without a dedicated catalog.
- `macUSB/Resources/Downloader.xcstrings` — downloader-owned text and feature-specific copies of shared labels, selected through the `Downloader` table.
- `macUSB/Resources/Creator.xcstrings` — the `Creator` table for USB execution/progress, cancellation/unmount recovery, and macOS, Windows, Linux, and raw-image helper workflow presentation.
- `macUSB/Resources/FinishUSB.xcstrings` — the `FinishUSB` table for results, final error cards, cleanup, guidance, ejection, and USB completion notifications.
- `macUSB/Shared/Localization/HelperWorkflowLocalizationKeys.swift` — shared app/daemon workflow presentation identifiers, legacy identifier normalization, stage mapping, and `Creator` extraction anchors.

## Bundled bootloader resources

- `macUSB/Resources/Bootloaders/macUSBoot/*` — pinned macUSBoot binary, manifest, and SHA-256 checksum bundled at `Contents/Resources/macUSBoot`.

## Update Trigger

Update when file responsibilities move, module boundaries change, or new runtime modules are introduced.
