# Diagnostic Logging Contract

This is the target contract for the staged unification of diagnostic logs. Existing log paths may use older wording and formatting until they are migrated. Feature references continue to define which events and details to record.

## Language

- Write app- and helper-authored diagnostic messages and stage labels in English, regardless of the selected UI language. Do not localize diagnostic messages.
- Preserve raw output from external tools, system error descriptions, file paths, and other source data verbatim. When that data is included in exported logs, identify its originating stage; the application-authored explanation around it remains in English.
- Keep messages readable and useful in exported diagnostics. Important app-side runtime events go through `AppLogging`.

## Line Format

- Keep the existing 24-hour local-time prefix `[HH:MM:SS]`.
- Immediately after the time prefix, add a space and a bracketed, uppercase English stage label. Follow it with a space and the English message:

  `[HH:MM:SS] [STAGE] Message`

- For an event belonging to a specific workflow, append its uppercase workflow name to the stage with an underscore: `[STAGE_WORKFLOW]`. Use the same workflow suffix throughout that operation, including errors. Use the base `[STAGE]` when no workflow has been identified or the event spans workflows.
- Append a separate `[HELPER]` tag after the stage for every diagnostic emitted by the privileged helper or forwarded from it, including its tool output. This tag identifies the source, not the operation. App-side registration, XPC, and repair logs use the `HELPER` stage without the extra source tag. If a helper-origin event also has the `HELPER` stage, keep both tags: `[HELPER] [HELPER]`.
- For a message containing multiple physical lines, repeat the time, stage, and optional helper-origin prefix on every line while keeping each line's source content intact.
- Stage and workflow names use uppercase English letters (`A`–`Z`), with one underscore between the stage and workflow. Do not use lowercase or title case.
- Use a stage label that identifies the operation producing the event, rather than the Swift file or logger implementation.
- Examples:

  `[14:32:08] [PERMISSIONS] Full Disk Access check started.`

  `[14:32:11] [ANALYSIS_MACOS] Selected source is a macOS installer image.`

  `[14:33:20] [ANALYSIS_WINDOWS] Windows installer image detected.`

  `[14:35:42] [USB_WINDOWS] Target disk validation passed.`

  `[14:35:47] [USB_WINDOWS] [HELPER] Target format completed.`

## Stage Labels

Use `APP` for startup and application lifecycle, `PERMISSIONS` for access and background-approval checks, `ANALYSIS` for source detection and compatibility, `USB` for target validation and media creation or cleanup, `DOWNLOADER` for installer discovery and download, `HELPER` for helper registration, XPC readiness, and repair, and `NOTIFICATIONS` for notification authorization and delivery. Add another short English label when an operation does not fit these stages, and use it consistently.

Choose the workflow suffix from the actual branch of work. Examples include `ANALYSIS_LINUX`, `USB_MACOS`, and `USB_PPC`; use the same pattern for other workflows.

The stage describes the work, even when a different component emits the line. For example, a helper diagnostic from a Windows USB creation workflow uses `USB_WINDOWS` plus the `HELPER` source tag; an app-side helper connection diagnostic uses the `HELPER` stage alone.

## Startup Block

The application starts each exported session with one English `APP` block. Every line carries the same local timestamp and stage prefix. The labels are aligned for scanning, and the values report the application version and build, macOS version, Mac model, and physical Mac architecture:

```text
[14:32:08] [APP] ┌─ macUSB session started
[14:32:08] [APP] │ App version   : 2.0 (123)
[14:32:08] [APP] │ macOS version : 26.0
[14:32:08] [APP] │ Mac model     : Mac16,1
[14:32:08] [APP] │ Architecture  : Apple Silicon (ARM64)
[14:32:08] [APP] └────────────────────────────────────
```

Use `Unknown` if the Mac architecture or model cannot be identified. This block is already implemented; other log paths still follow the staged migration noted above.

Full Disk Access check/probe lines, automatic helper update lifecycle lines, app-side XPC helper code-signing requirement diagnostics, and ensure-ready XPC health checks also use the target format. Analysis-screen diagnostics, including source selection, macOS/Windows/Linux recognition, manual raw-image selection, SHA-256 calculation, source-image cleanup, and USB target selection/validation, use the target format. The shared helper repair flow still uses its existing logging path during this staged migration.

USB creation diagnostics from the installation summary through the finish screen use `USB` with the selected workflow suffix. macOS suffixes are `MACOS`, `SIERRA`, `CATALINA`, `LEGACYRESTORE`, `MAVERICKS`, and `PPC`; Windows uses `WINDOWS`, recognized Linux uses `LINUX`, and manual raw-image writing uses `RAW`. App-side creation and finish events pass through `AppLogging`. Privileged USB workflow event lines, including external tool output, receive the same workflow suffix and the `[HELPER]` source tag when forwarded by the app. Helper IPC payloads and localized UI messages remain unchanged.

## Update Trigger

Update when the log language, exported line format, or stage-label policy changes. Keep feature-specific logging expectations in their existing references.
