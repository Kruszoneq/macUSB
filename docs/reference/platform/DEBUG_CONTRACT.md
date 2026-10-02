# DEBUG Contract

## Build Visibility

DEBUG UI/actions exist only in `#if DEBUG` builds.
Release must not expose DEBUG controls.

## UI Text

Text displayed exclusively in DEBUG uses untranslated English literals from code, including downloader controls, retention statuses, summary values, and cancellation messages. These texts have no localization keys or string-catalog entries and are excluded from automatic string extraction.

## Runtime Safety

Debug routing and helper/debug convenience actions must remain deterministic and must not change production semantics.
Debug helper identity must stay isolated from Release (`bundle id`, daemon plist name, daemon label, mach service).

## Current Examples

- debug-only menu shortcuts with verbatim English labels,
- debug temp-folder helpers,
- an `Open Diagnostic Logs Folder` menu action that opens the session-log directory in Finder,
- debug-only downloader toggles.
- disabled finish-screen ejection, with a verbatim `DEBUG` action label and no localization entry.
- the copied-data metric in the DEBUG menu, missing-temp-folder alert, Xcode-only helper location status, and registration/recovery guidance, all displayed as English literals.

The diagnostic-log folder action uses an English label without localization and appears only in Debug builds.

## Update Trigger

Update when debug surfaces, routing payloads, or debug-safety boundaries change.
