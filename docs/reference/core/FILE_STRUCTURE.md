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
- Reserved naming for future non-macOS support: `AnalysisLogicLinuxCompatibility.swift` (not implemented yet).

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
- `macUSBHelper/DownloaderAssembly/*`

## Localization catalog

- `macUSB/Resources/Localizable.xcstrings`

## Update Trigger

Update when file responsibilities move, module boundaries change, or new runtime modules are introduced.
