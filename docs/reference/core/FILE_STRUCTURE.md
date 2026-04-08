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
