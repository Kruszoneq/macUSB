# DEBUG Contract

## Build Visibility

DEBUG UI/actions exist only in `#if DEBUG` builds.
Release must not expose DEBUG controls.

## Runtime Safety

Debug routing and helper/debug convenience actions must remain deterministic and must not change production semantics.
Debug helper identity must stay isolated from Release (`bundle id`, daemon plist name, daemon label, mach service).

## Current Examples

- debug-only menu shortcuts,
- debug temp-folder helpers,
- an `Open Diagnostic Logs Folder` menu action that opens the session-log directory in Finder,
- debug-only downloader toggles.

The diagnostic-log folder action uses an English label without localization and appears only in Debug builds.

## Update Trigger

Update when debug surfaces, routing payloads, or debug-safety boundaries change.
