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

### Analysis layout

- `macUSB/Features/Analysis/SystemAnalysisView.swift` — analysis UI screen.
- `macUSB/Features/Analysis/AnalysisLogic.swift` — analysis state + facade API for UI bindings.
- `macUSB/Features/Analysis/AnalysisSelectionHandoff.swift` — handoff bridge for pending installer URL from downloader flow.
- `macUSB/Features/Analysis/AnalysisNotifications.swift` — shared `Notification.Name` constants used by analysis/flow wiring.
- `macUSB/Features/Analysis/Logic/AnalysisLogicFileSelection.swift` — file selection/drop/open-panel logic.
- `macUSB/Features/Analysis/Logic/AnalysisLogicAnalysisFlow.swift` — orchestration of analysis execution for `.app` and image sources.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSCompatibility.swift` — macOS-only compatibility/version-family detection rules and flag mapping.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSImageMounting.swift` — image mounting + mounted-source guard + legacy image read logic.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSInstallerMetadata.swift` — installer metadata/version parsing and USB capacity mapping helpers.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSInstallerIcon.swift` — installer icon discovery.
- `macUSB/Features/Analysis/Logic/AnalysisLogicUsbDrives.swift` — USB drive enumeration/refresh/capacity checks.
- `macUSB/Features/Analysis/Logic/macOS/AnalysisLogicMacOSLifecycle.swift` — reset/cleanup/manual Tiger flow helpers.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxDetection.swift` — Linux fallback entrypoint and result shaping.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxMetadata.swift` — bounded Linux metadata reads from mounted ISO/CDR.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxClassification.swift` — Linux distro/version/edition classification rules.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxArchitecture.swift` — Linux architecture normalization and ARM flag mapping.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxDisplayName.swift` — final Linux display-name formatting policy.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxLifecycle.swift` — Linux state reset/apply helpers.
- `macUSB/Features/Analysis/Logic/Linux/AnalysisLogicLinuxInstallationHandoff.swift` — Linux install context handoff for USB creation flow.

### Installation layout

- `macUSB/Features/Installation/UniversalInstallationView.swift` — shared summary screen before start.
- `macUSB/Features/Installation/CreationProgressView.swift` — shared stage/progress UI.
- `macUSB/Features/Installation/CreatorLogic.swift` — shared install actions/cancel/cleanup orchestration.
- `macUSB/Features/Installation/CreatorHelperLogic.swift` — shared helper workflow orchestration and transfer metrics.
- `macUSB/Features/Installation/Linux/LinuxInstallationFlowContext.swift` — Linux flow context payload.
- `macUSB/Features/Installation/Linux/CreatorLinuxLogic.swift` — Linux-specific summary/cleanup helpers.
- `macUSB/Features/Installation/Linux/CreatorLinuxHelperLogic.swift` — Linux helper request construction and start routing.
- `macUSB/Features/Installation/Linux/CreationProgressLinuxMapping.swift` — Linux stage mapping for shared progress UI.

### Shared UI layout

- `macUSB/Shared/UI/TouchBar/TouchbarSupport.swift` — global, fixed Touch Bar configuration (app branding).

### Analysis docs

- `docs/reference/features/analysis/ANALYSIS_COMPATIBILITY.md` — analysis contract and routing invariants.
- `docs/reference/features/analysis/LINUX_ANALYSIS_FLOW.md` — detailed Linux fallback flow and rule set.

### Downloader layout

- `macUSB/Features/Downloader/MacOSDownloaderCoordinator.swift`
- `macUSB/Features/Downloader/UI/*`
- `macUSB/Features/Downloader/Logic/Discovery/*`
- `macUSB/Features/Downloader/Logic/Download/*`
- `macUSB/Features/Downloader/Logic/Assembly/*`
- `macUSB/Features/Downloader/Logic/MacOSVerificationLogic.swift`
- `macUSB/Features/Downloader/Logic/MacOSCleanupLogic.swift`

### Helper (app-side)

- `macUSB/Shared/Services/Helper/HelperIPC.swift`
- `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift`
- `macUSB/Shared/Services/Helper/HelperServiceManager.swift`
- `macUSB/Shared/Services/Helper/HelperService/*`

### Helper (daemon)

- `macUSBHelper/main.swift`
- `macUSBHelper/IPC/*`
- `macUSBHelper/Service/*`
- `macUSBHelper/Workflow/*`
- `macUSBHelper/Workflow/Linux/*` — Linux raw-copy stage builder, parser, and disk ops.
- `macUSBHelper/DownloaderAssembly/*`

## Localization catalog

- `macUSB/Resources/Localizable.xcstrings`

## Update Trigger

Update when file responsibilities move, module boundaries change, or new runtime modules are introduced.
