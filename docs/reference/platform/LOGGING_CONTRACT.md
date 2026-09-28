# Diagnostic Logging Contract

This reference describes the diagnostic logging currently emitted by the app and privileged helper. Feature references define which events and details are recorded. The current workflow-label and source-output exceptions are stated below.

## Language

- App- and helper-authored diagnostic messages and stage labels use English, regardless of the selected UI language. Diagnostic messages are not localized.
- Raw output from external tools, system error descriptions, file paths, and other source data can retain their original language. Exported lines identify their stage; application-authored explanations around source data are in English. The legacy downloader assembly output normalization is described under Current Exceptions.
- Keep messages readable and useful in exported diagnostics. Important app-side runtime events go through `AppLogging`.

## Export Buffer

`AppLogging` retains the most recent 10,000 appended log entries in memory for diagnostic export. Older entries are removed when the buffer exceeds this limit.
The diagnostic export saves UTF-8 text with the `.log` extension. The Save panel suggests a name in the form `macUSB-yymmdd-hhmmss.log`.
After the user confirms the Save panel, the app appends `[HH:MM:SS] [APP] Diagnostic log generated for export.` to the in-memory buffer and uses that entry as the final line of the exported snapshot.
The app also appends each entry to `~/Library/Application Support/<bundle identifier>/DiagnosticLogs/current-session.log` as it is recorded. After termination cleanup and its operation-token finish log, normal termination appends an `[APP]` separator followed by the final result: `Application terminated successfully.` or `Application terminated with cleanup errors.` The latter means temporary-directory removal, source-image discovery, or image detachment failed; these errors do not prevent exit. The app then rewrites the file from the bounded export buffer, including that final result. At the next launch, the current file becomes `previous-session.log`; only the immediately preceding session is retained. A session interrupted before normal termination can still be exported from the entries already written to disk, but has no termination result marker.
The Help menu offers a separate previous-session export directly below the current-session export. It is disabled when the immediately preceding session has no stored logs. The previous-session export reads the saved file without adding the current session's export marker and suggests `macUSB-previous-session-yymmdd-hhmmss.log`.

## Line Format

- Keep the existing 24-hour local-time prefix `[HH:MM:SS]`.
- Immediately after the time prefix, add a space and a bracketed, uppercase English stage label. Follow it with a space and the English message:

  `[HH:MM:SS] [STAGE] Message`

- When a call supplies a workflow, `AppLogging` appends its uppercase name to the stage with an underscore: `[STAGE_WORKFLOW]`. Calls without a workflow use the base `[STAGE]`. Most workflow-specific event and error calls supply the selected workflow; protected-operation token exceptions are described below.
- Direct helper diagnostics and helper progress or tool-output lines forwarded into the app carry a separate `[HELPER]` tag after the stage. This tag identifies the source, not the operation. App-side registration, XPC, and repair logs use the `HELPER` stage without the extra source tag. If a direct helper diagnostic also has the `HELPER` stage, it carries both tags: `[HELPER] [HELPER]`. App-side error wrappers containing a helper result description are described under Current Exceptions.
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

The app currently emits `APP` for startup, application lifecycle, update checks, and default protected-operation tokens; `PERMISSIONS` for access and background-approval checks; `ANALYSIS` for source detection and compatibility; `USB` for target validation and media creation or cleanup; `DOWNLOADER` for installer discovery and download; and `HELPER` for helper registration, XPC readiness, and repair. Notification authorization and delivery currently emit no dedicated diagnostic lines or `NOTIFICATIONS` stage.

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

Use `Unknown` if the Mac architecture or model cannot be identified.

Full Disk Access check/probe lines, automatic helper update lifecycle lines, app-side XPC helper code-signing requirement diagnostics, and ensure-ready XPC health checks use the line format above. Analysis-screen diagnostics, including source selection, macOS/Windows/Linux recognition, manual raw-image selection, SHA-256 calculation, source-image cleanup, and USB target selection/validation, use that format. Manual and automatic full helper repair diagnostics use English `[HELPER_REPAIR]` lines; its separate technical-details alert uses the same prefix. Localized repair messages remain presentation data.

Startup and menu update checks use English `[APP]` diagnostics for start, newer-version detection, no-newer-version results, and request or metadata failures. Their alerts remain localized.

Daemon-side system log messages use the same timestamp, operation stage, and `[HELPER]` source tag. XPC trust and process lifecycle use `[HELPER] [HELPER]`. Direct Rosetta and Linux post-mount diagnostics use `[USB] [HELPER]` because the daemon does not receive the app-only presentation workflow label; the corresponding forwarded USB progress and results receive their selected workflow suffix in the app's exported log.

Helper readiness and IPC reload diagnostics use English `[HELPER]` lines. `SMAppService` status values in those lines use English diagnostic names; localized status descriptions remain in the UI. App termination coordination and cleanup lifecycle use English `[APP]` lines; tracked source-image detach events retain their `ANALYSIS` label and known image-family suffix. Protected-operation token start and finish lines use the stage and workflow supplied by their caller; without either override they use `[APP]`. USB creation, helper repair, finish cleanup, and USB eject supply their operation labels.

USB creation diagnostics from the installation summary through the finish screen use `USB` with the selected workflow suffix. macOS suffixes are `MACOS`, `SIERRA`, `CATALINA`, `LEGACYRESTORE`, `MAVERICKS`, and `PPC`; Windows uses `WINDOWS`, recognized Linux uses `LINUX`, and manual raw-image writing uses `RAW`. App-side creation and finish events pass through `AppLogging`. Privileged USB workflow event lines, including external tool output, receive the same workflow suffix and the `[HELPER]` source tag when forwarded by the app. Helper IPC payloads and localized UI messages remain unchanged.

Downloader event diagnostics use `DOWNLOADER` for window and prerequisite events before a workflow is identified, `DOWNLOADER_DISCOVERY` for installer discovery, and `DOWNLOADER_MODERN`, `DOWNLOADER_LEGACY`, or `DOWNLOADER_OLDEST` for the selected installer distribution workflow. App-side lines pass through `AppLogging`; forwarded helper assembly and tool-output lines append `[HELPER]`. A missing helper-cleanup confirmation produces an English app-authored error and, when available, a separate `[HELPER]` line containing the helper's original error text. UI localization keys and helper status payloads remain presentation data.

## New Logging Paths

When adding a feature or a logging path:

- Send app-side diagnostics through `AppLogging`; let it add the timestamp, stage, workflow suffix, and per-line prefix. Use `HelperDiagnosticLogging` for direct daemon system logs.
- Write app- and helper-authored diagnostic text in English, independently of the UI language. Keep localized UI text out of diagnostic messages. Retain raw tool output, system error descriptions, paths, and other source data in their original form and identify their source.
- Choose the stage for the operation being performed. Pass its workflow suffix to every log once the workflow is known, including errors, cleanup, and protected-operation token start and finish. Use the base stage only before workflow identification or for work that genuinely spans workflows.
- Mark every new helper-origin diagnostic forwarded into the app with `helperOrigin: true`, including progress, tool output, and result details. Direct daemon diagnostics carry the same source tag. App-authored helper registration, XPC, and repair diagnostics use the `HELPER` stage without a helper-origin tag.
- Record enough context to explain the operation and its result without using diagnostic output as the source of UI stage or status text. Update the relevant feature reference when the new path changes which events or details are logged.

The exceptions below document existing paths; they are not templates for new logging code.

## Current Exceptions

- The protected-operation registry defaults to `[APP]` when a caller supplies no stage or workflow. Its analysis and manual SHA-256 tokens, tracked-source-image cleanup token, downloader-window token, downloader assembly and cleanup tokens, Rosetta tokens, and app-termination cleanup token currently use that default. Their related event logs may carry `ANALYSIS`, `DOWNLOADER`, `USB`, or another operation stage.
- The app-side legacy downloader assembly process combines captured standard output and standard error with a newline and trims leading and trailing whitespace before logging the result. The logged content is therefore not a byte-for-byte copy of the original process output.
- On a failed USB workflow result, the app writes `Helper workflow failed: <errorMessage>` with the selected `[USB_WORKFLOW]` label and no separate `[HELPER]` tag. The embedded helper result description is source data and can retain its original language. Some app-side Rosetta failure lines similarly include a helper or system error description without the source tag.

## Update Trigger

Update when the log language, exported line format, or stage-label policy changes. Keep feature-specific logging expectations in their existing references.
