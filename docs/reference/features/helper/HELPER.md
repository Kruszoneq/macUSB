# macUSB Helper Reference

This document is a dedicated runtime and maintenance reference for the privileged helper in macUSB.

It is intentionally split from other docs:
- Process, commit, and release workflow rules are defined in `docs/AGENTS.md`.
- Global runtime documentation map is in `docs/reference/README.md`.
- This file focuses only on helper architecture, behavior, and safe change practices.

## Table of Contents
1. [Purpose and Scope](#1-purpose-and-scope)
2. [Quick Rules for Agents](#2-quick-rules-for-agents)
3. [Top Rule: Functional Isolation (MUST)](#3-top-rule-functional-isolation-must)
4. [Helper Architecture Overview](#4-helper-architecture-overview)
5. [IPC Contract and Types](#5-ipc-contract-and-types)
6. [Runtime Flows](#6-runtime-flows)
7. [File Structure and Responsibilities](#7-file-structure-and-responsibilities)
8. [Error Handling and Recovery](#8-error-handling-and-recovery)
9. [Logging and Diagnostics](#9-logging-and-diagnostics)
10. [DEBUG vs Release Behavior](#10-debug-vs-release-behavior)
11. [Change Checklists (Mandatory)](#11-change-checklists-mandatory)
12. [Verification Playbook (Smoke)](#12-verification-playbook-smoke)
13. [When to Update This Document](#13-when-to-update-this-document)
14. [Frequent AI Pitfalls](#14-frequent-ai-pitfalls)

---

## 1. Purpose and Scope

This reference is for safe, predictable helper work in macUSB.

It documents:
- helper architecture and boundaries,
- stable IPC contracts and payloads,
- runtime flows and invariants,
- safe verification after changes.

Out of scope:
- commit policy details,
- release/changelog policy details,
- non-helper product behavior outside helper touchpoints.

---

## 2. Quick Rules for Agents

- Read `docs/AGENTS.md` before any helper modification.
- Read helper-adjacent runtime files from `docs/reference/README.md` before changing behavior.
- Keep helper behavior and IPC semantics stable unless explicitly requested by the user.
- Treat helper and helper-related file operations as high-risk areas.
- Verify cross-feature safety after every helper change.

---

## 3. Top Rule: Functional Isolation (MUST)

**Every helper change must be functionally isolated.**

After each change, it is mandatory to verify that unrelated feature logic was not touched or regressed.

Examples:
- Downloader work must not change USB creation behavior.
- USB workflow work must not change downloader behavior.
- Repair UI changes must not alter repair logic.

---

## 4. Helper Architecture Overview

The helper system has two runtime layers:

- App-side integration in `macUSB/Shared/Services/Helper/*`.
- Privileged daemon runtime in `macUSBHelper/*`.

High-level model:
- App-side validates readiness, manages registration/repair, and communicates via XPC.
- Daemon executes privileged workflows and sends progress/result events back to app-side.

Core invariant:
- No terminal fallback privileged path.
- Privileged operations must run through `SMAppService` plus launchd helper and XPC.

---

## 5. IPC Contract and Types

Primary protocols:
- `MacUSBPrivilegedHelperToolXPCProtocol`
- `MacUSBPrivilegedHelperClientXPCProtocol`

Primary request types:
- `HelperWorkflowRequestPayload` for USB workflows.
- `DownloaderAssemblyRequestPayload` for downloader `.pkg` to `.app` assembly.
- `DownloaderCleanupRequestPayload` for downloader session-temp cleanup.

Primary progress/result types:
- `HelperProgressEventPayload`
- `HelperWorkflowResultPayload`
- `DownloaderAssemblyProgressPayload`
- `DownloaderAssemblyResultPayload`
- `DownloaderCleanupResultPayload`

Serialization:
- `HelperXPCCodec` (`JSONEncoder`/`JSONDecoder`, ISO-8601 dates).

Contract invariants:
- Stage keys and status keys are treated as stable technical identifiers.
- App-side localization rendering must stay compatible with helper payload content.
- IPC shape changes are major helper changes and require explicit confirmation before implementation.

---

## 6. Runtime Flows

### Single Active Task Invariant
- Helper executes only one privileged task at a time across USB workflow, downloader assembly, and downloader cleanup requests.
- If another task is already active, the new request is rejected with conflict semantics and must be retried by app-side flow when appropriate.

### Ensure-Ready Flow
- Entry point: `HelperServiceManager` ensure-ready path.
- Checks app location and helper service status.
- Handles status states (`enabled`, `requiresApproval`, `notRegistered`, `notFound`).
- Performs health validation via XPC.
- Uses controlled recovery when enabled service is unhealthy.

### Startup Auto-Repair Flow (version/build change)
- Entry point: `bootstrapIfNeededAtStartup`.
- After successful non-interactive ensure-ready, app compares current app fingerprint (`CFBundleShortVersionString` + `CFBundleVersion`) with last successful helper-repair fingerprint stored in `UserDefaults`.
- If fingerprint changed, or no previous fingerprint exists (upgrade from older app versions), app runs automatic full helper repair in background.
- Successful automatic repair updates stored fingerprint and remains visible only in logs.
- Failed automatic repair presents one warning `NSAlert` with guidance to run `Tools → Repair helper` manually.

### Hard-Repair Flow
- Triggered from Tools menu repair action.
- Full reset sequence: unregister, stabilization delay, teardown validation, register, health-check.
- Includes bounded retry/backoff for transient registration/health race conditions.
- Produces detailed progress logs for diagnostics.
- UI surface uses `NSAlert`:
  - in-progress informational alert (non-dismissable action button while repair is running),
  - automatic transition to final status alert after completion,
  - failure path offers an additional details alert with technical repair logs.

### USB Workflow Flow
- App sends `HelperWorkflowRequestPayload`.
- Daemon executes staged workflow (`prepare`, format/restore/createinstallmedia/copy/finalize patterns by workflow kind, plus Linux raw-copy branch).
- Progress events are emitted with stage/status keys and percent updates.
- Cancellation and failure return deterministic result payloads.

### Downloader Assembly Flow
- App sends `DownloaderAssemblyRequestPayload`.
- Daemon runs installer-based assembly and file operations.
- Daemon normalizes ownership of the final installer `.app` to requester UID.
- Progress and final result are reported over dedicated downloader assembly IPC methods.

### Downloader Final Cleanup Flow
- App sends `DownloaderCleanupRequestPayload` in the final cleanup stage.
- Daemon removes the session temp directory and returns `DownloaderCleanupResultPayload`.
- Cleanup is executed as the last downloader stage before summary (not inside assembly stage).

---

## 7. File Structure and Responsibilities

App-side helper integration:

- `macUSB/Shared/Services/Helper/HelperIPC.swift`
  - app-side IPC contracts and compatibility decode logic.
- `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift`
  - XPC connection handling and app-facing helper calls.
- `macUSB/Shared/Services/Helper/HelperServiceManager.swift`
  - central state/facade for helper lifecycle.
- `macUSB/Shared/Services/Helper/HelperService/HelperServiceBootstrap.swift`
  - startup bootstrap and approval-related helper lifecycle hooks.
- `macUSB/Shared/Services/Helper/HelperService/HelperServiceEnsureReadyFlow.swift`
  - readiness and registration flow.
- `macUSB/Shared/Services/Helper/HelperService/HelperServiceRepairFlow.swift`
  - hard repair flow and retry/stabilization logic.
- `macUSB/Shared/Services/Helper/HelperService/HelperServiceStatusUI.swift`
  - helper status UI surfaces.
- `macUSB/Shared/Services/Helper/HelperService/HelperServiceRepairUI.swift`
  - repair alert orchestration logic (progress/status/details).
- `macUSB/Shared/Services/Helper/HelperService/HelperServiceRepairPanelView.swift`
  - legacy repair panel SwiftUI view and presentation model (not used in current repair UX flow).
- `macUSB/Shared/Services/Helper/HelperService/HelperServiceDiagnostics.swift`
  - diagnostic helpers and error interpretation.

Daemon helper runtime:

- `macUSBHelper/main.swift`
  - listener bootstrap entry only.
- `macUSBHelper/IPC/HelperIPC.swift`
  - daemon-side IPC contracts and payload types.
- `macUSBHelper/Service/PrivilegedHelperService.swift`
  - XPC service entrypoints and active executor lifecycle, including downloader session cleanup endpoint.
- `macUSBHelper/Service/HelperListenerDelegate.swift`
  - listener delegate and connection wiring.
- `macUSBHelper/Workflow/HelperWorkflowExecutor.swift`
  - USB workflow execution orchestration and cancellation.
- `macUSBHelper/Workflow/HelperWorkflowStages.swift`
  - context preparation and stage graph construction.
- `macUSBHelper/Workflow/HelperWorkflowProgressParsing.swift`
  - command output parsing to percent/status.
- `macUSBHelper/Workflow/HelperWorkflowDiskResolution.swift`
  - disk resolution and target mapping helpers.
- `macUSBHelper/Workflow/HelperWorkflowFileOperations.swift`
  - helper-side file operations and command wrappers.
- `macUSBHelper/Workflow/Linux/HelperWorkflowLinuxStages.swift`
  - Linux-specific stage graph (`linux_unmount_target`, `linux_raw_copy`).
- `macUSBHelper/Workflow/Linux/HelperWorkflowLinuxProgressParsing.swift`
  - Linux raw-copy (`dd`) progress parsing and percent mapping.
- `macUSBHelper/Workflow/Linux/HelperWorkflowLinuxDiskOps.swift`
  - Linux source/target disk resolution helpers.
- `macUSBHelper/DownloaderAssembly/DownloaderAssemblyExecutor.swift`
  - downloader assembly execution orchestration and final `.app` ownership normalization.
- `macUSBHelper/DownloaderAssembly/DownloaderAssemblyProcess.swift`
  - installer output handling, progress mapping, app location logic.

---

## 8. Error Handling and Recovery

Design expectations:
- Errors are explicit and stage-aware.
- Cancellation is deterministic and not treated as generic failure.
- Recovery should be bounded and observable, not infinite retry loops.

Important behavior:
- Ensure-ready attempts recovery when health check fails after enabled status.
- Hard-repair validates teardown before register and validates health after register.
- USB and downloader assembly return structured result payloads.
- Cleanup remains deterministic in both success and failure paths.

---

## 9. Logging and Diagnostics

Rules:
- Important runtime events should be routed through `AppLogging` on app-side.
- Repair flow should produce readable operational logs.
- Helper live tool output is diagnostic and must not become the UI source of truth for stage semantics.

Diagnostics should allow answering:
- Which phase failed.
- What status the helper had at that moment.
- Whether XPC health passed or failed.
- Whether recovery was attempted and with what outcome.
- Whether startup auto-repair was triggered by app fingerprint change or by missing previous fingerprint.

---

## 10. DEBUG vs Release Behavior

- DEBUG-only helper/debug UI must not leak into Release.
- Runtime helper invariants are identical across build configurations.
- Any debug convenience path must not alter production helper semantics.
- DEBUG and Release must use isolated helper identity tuples (`bundle id`, daemon plist name, daemon label, mach service) to avoid BTM/TCC cross-environment collisions.

---

## 11. Change Checklists (Mandatory)

### Pre-Change Checklist
- [ ] Module boundaries are identified before edits.
- [ ] Scope is confirmed as helper-only or helper-related.
- [ ] No unrelated feature files are included in planned changes.
- [ ] IPC/stage/status compatibility impact is evaluated.

### Post-Change Checklist
- [ ] Debug build succeeds.
- [ ] Helper readiness flow works.
- [ ] Helper repair flow works end-to-end.
- [ ] USB helper workflow smoke path works.
- [ ] Downloader helper assembly smoke path works.
- [ ] Cross-feature safety is verified:
- [ ] Downloader logic unchanged when editing USB helper behavior.
- [ ] USB workflow logic unchanged when editing downloader/helper behavior.

### Documentation Checklist
- [ ] `docs/reference/README.md` and helper-related runtime docs remain consistent with helper behavior.
- [ ] Stage keys, status keys, and IPC names in docs match code.
- [ ] This `HELPER.md` file reflects current helper structure and flows.

---

## 12. Verification Playbook (Smoke)

Recommended baseline command:

```bash
xcodebuild -project macUSB.xcodeproj -scheme macUSB -configuration Debug -destination 'platform=macOS' build
```

Manual smoke path:
- Helper status check from app menu.
- Helper repair run from app menu.
- USB creation flow start and progress reporting sanity check.
- Downloader assembly flow sanity check.
- Cancel path sanity for active helper operations.

Expected result:
- No regressions in unrelated features.
- No IPC mismatches.
- Stage/status rendering remains coherent.

---

## 13. When to Update This Document

Update `HELPER.md` when:
- helper file layout changes,
- IPC contracts/types change,
- stage/status key semantics change (including Linux stage keys),
- repair lifecycle behavior changes,
- downloader assembly behavior in helper changes,
- helper verification procedure changes.

Do not duplicate process-policy details here; keep those in `docs/AGENTS.md`.

---

## 14. Frequent AI Pitfalls

- Mixing process rules (`AGENTS`) with runtime behavior docs (`reference`).
- Modifying helper-adjacent UI files and accidentally changing helper logic.
- Changing payload fields or stage/status semantics without coordinated app-side handling.
- Treating debug-only behavior as production behavior.
- Skipping cross-feature verification after helper modifications.

Use this document as the first checkpoint before any helper change and as a closure checklist after implementation.
