# macUSB Reference Index

This index is the primary entry point for runtime documentation.

Use this map before reading feature-specific references:
- Process/commit/PR/changelog rules for agents: `docs/AGENTS.md`
- Helper-only runtime: `docs/reference/features/helper/HELPER.md`
- Downloader-only runtime: `docs/reference/features/downloader/DOWNLOADER.md`

## Read By Topic

### Global orientation
- `docs/reference/core/APP_RUNTIME_OVERVIEW.md`
- `docs/reference/core/USER_FLOW.md`
- `docs/reference/core/FILE_STRUCTURE.md`
- `docs/reference/core/RISK_AREAS.md`

### Permissions and startup gating
- `docs/reference/platform/PERMISSIONS_AND_BACKGROUND.md`

### UI and visual consistency
- `docs/reference/design/DESIGN_SYSTEM.md`

### Analysis and compatibility routing
- `docs/reference/features/analysis/ANALYSIS_COMPATIBILITY.md`
- `docs/reference/features/analysis/LINUX_ANALYSIS_FLOW.md`

### USB target validation and capacity
- `docs/reference/features/usb/USB_VALIDATION_AND_CAPACITY.md`

### USB creation execution
- `docs/reference/features/usb/USB_CREATION_WORKFLOWS.md`

### Finish and cleanup behavior
- `docs/reference/features/usb/FINISH_AND_CLEANUP.md`

### Localization
- `docs/reference/platform/LOCALIZATION_CONTRACT.md`

### Notifications
- `docs/reference/platform/NOTIFICATIONS_CONTRACT.md`

### Debug behavior
- `docs/reference/platform/DEBUG_CONTRACT.md`

## Logging Rule

Logging expectations are documented inside each feature reference instead of one global logging chapter:
- Analysis logs: `ANALYSIS_COMPATIBILITY.md`
- USB creation logs: `USB_CREATION_WORKFLOWS.md`
- Finish/cleanup logs: `FINISH_AND_CLEANUP.md`
- Downloader logs: `features/downloader/DOWNLOADER.md`
- Helper logs: `features/helper/HELPER.md`
- Permissions/startup logs: `platform/PERMISSIONS_AND_BACKGROUND.md`

## Maintenance Rule

When behavior changes, update the smallest relevant reference file(s) from this index.
If a change is cross-cutting, update all affected references and keep this index coherent.
