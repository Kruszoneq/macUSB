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
- debug-only downloader toggles.

## Update Trigger

Update when debug surfaces, routing payloads, or debug-safety boundaries change.
