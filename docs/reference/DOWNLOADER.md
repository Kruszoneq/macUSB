# macUSB Downloader Reference

This document describes the runtime behavior, UI contract, and technical pipeline of the macUSB downloader module.

Scope note:
- This file is focused on downloader behavior only.
- Process/commit rules are in `docs/AGENTS.md`.
- Global app runtime contract is in `docs/reference/APPLICATION_REFERENCE.md`.

## Table of Contents
1. [Purpose and Scope](#1-purpose-and-scope)
2. [Top Rules and Invariants](#2-top-rules-and-invariants)
3. [Architecture Overview](#3-architecture-overview)
4. [Data Model and State](#4-data-model-and-state)
5. [Discovery Flow (Apple Catalog)](#5-discovery-flow-apple-catalog)
6. [Monterey Production Download Flow](#6-monterey-production-download-flow)
7. [Verification Strategy](#7-verification-strategy)
8. [Helper Integration](#8-helper-integration)
9. [UI Contract](#9-ui-contract)
10. [Error Handling and Partial Success](#10-error-handling-and-partial-success)
11. [DEBUG Behavior](#11-debug-behavior)
12. [Logging and Diagnostics](#12-logging-and-diagnostics)
13. [File Structure](#13-file-structure)
14. [Cross-Feature Safety Checklist](#14-cross-feature-safety-checklist)
15. [How to Extend Beyond Monterey](#15-how-to-extend-beyond-monterey)

---

## 1. Purpose and Scope

Downloader provides:
- official macOS/OS X installer discovery from Apple sources,
- staged download/verify/build flow,
- final installer `.app` creation and target placement,
- deterministic temp cleanup and end-state summary.

Current production scope:
- full download pipeline is enabled for selected Monterey entries,
- discovery includes broad Apple-official stable entries across families.

---

## 2. Top Rules and Invariants

- Do not modify USB creation logic while working on downloader.
- Do not modify analysis logic while working on downloader.
- Downloader network sources must stay Apple-official allowlisted endpoints.
- Discovery runs on entering downloader window, not at app startup.
- Downloader UI must remain stylistically aligned with app design system.
- Final cleanup stage must be explicit and ordered as the last stage before summary.

---

## 3. Architecture Overview

Downloader split:
- Coordinator:
  - `MacOSDownloaderWindowManager` manages sheet presentation and lifecycle.
- UI:
  - window shell, list view, process view, summary view.
- Logic:
  - discovery, download, verification, assembly, cleanup.
- Helper bridge:
  - privileged assembly and privileged final cleanup over XPC.

Runtime orchestration:
- `MacOSDownloaderWindowShellView` owns:
  - `MacOSDownloaderLogic` for discovery,
  - `MontereyDownloadFlowModel` for staged download pipeline.

---

## 4. Data Model and State

Core models:
- `MacOSInstallerEntry`
  - identity, family, display name, version, build, source URL, optional product ID.
- `MacOSInstallerFamilyGroup`
  - grouped installer entries by system family.
- `DownloaderDiscoveryState`
  - `idle`, `loading`, `loaded`, `failed`, `cancelled`.
- `DownloadManifest`
  - product ID, system identity, package list, total expected bytes.
- `DownloadManifestItem`
  - package name, URL, expected size, digest metadata, optional `integrityDataURL`.

Process runtime state:
- `DownloadSessionState`
  - `idle`, `running`, `completed`, `failed`, `cancelled`.
- Stages:
  - `connection`, `downloading`, `verifying`, `buildingInstaller`, `copyingInstaller`, `cleanup`.

---

## 5. Discovery Flow (Apple Catalog)

Discovery pipeline (`MacOSDiscoveryLogic`):
1. Download Apple catalog (`swscan.apple.com`).
2. Parse InstallAssistant candidates from products metadata.
3. Parse `.dist` metadata from Apple distribution hosts.
4. Filter to stable entries (exclude pre-release markers).
5. Deduplicate by normalized identity.
6. Enrich legacy official entries from Apple Support list.
7. Probe installer sizes (catalog-prefill + network probe fallback).
8. Group by family and sort newest-first.

Discovery UX contract:
- starts automatically on entering downloader window,
- inline progress panel is shown in list area,
- cancel is available during scanning,
- after completion panel transitions out and list appears.

---

## 6. Monterey Production Download Flow

Monterey pipeline (`MontereyDownloadFlowModel`):
1. Connection / preflight
  - fetch real manifest for selected Monterey entry,
  - validate temporary disk capacity against total expected bytes + reserve.
2. Sequential file download
  - one file at a time,
  - progress %, speed sampling, transferred bytes text,
  - staged under `macUSB_temp/downloads/<session_id>/payload`.
3. File verification
  - size validation for each file,
  - IntegrityData/chunklist verification when available,
  - digest fallback and package-signature fallback where needed.
4. Installer build and move
  - helper-based `.pkg` to `.app` assembly,
  - final move to configured destination folder.
5. Final cleanup
  - dedicated helper-side cleanup of session temp directory,
  - executed as last stage before summary.

Summary:
- shows transfer, average speed, duration, and output file name,
- exposes Finder shortcut to destination folder.

---

## 7. Verification Strategy

Per-file verification order:
1. local presence and exact size check,
2. IntegrityData chunklist validation (`SHA-256` per chunk) when available,
3. digest fallback from manifest metadata if needed,
4. package signature check (`pkgutil`) fallback for package-specific mismatch cases.

Final installer verification:
- non-blocking code-signature check (`codesign`) for diagnostics,
- fallback package signature diagnostics when legacy signature warnings occur,
- expected build check from installer metadata with controlled compatibility alias handling.

Design intent:
- strict integrity for downloaded payload,
- pragmatic non-blocking diagnostics for legacy signature edge cases in final `.app`.

---

## 8. Helper Integration

Downloader uses dedicated helper operations:
- Assembly:
  - request type: `DownloaderAssemblyRequestPayload`,
  - progress: `DownloaderAssemblyProgressPayload`,
  - result: `DownloaderAssemblyResultPayload`.
- Final cleanup:
  - request type: `DownloaderCleanupRequestPayload`,
  - result: `DownloaderCleanupResultPayload`.

Helper responsibilities in downloader flow:
- build installer `.app` from package,
- move installer to destination,
- normalize final `.app` ownership to requester UID,
- perform final privileged cleanup of session temp directory.

---

## 9. UI Contract

Window:
- fixed-width sheet from coordinator,
- app-like liquid/glass-compatible surfaces and tokens.

List screen:
- grouped families,
- default mode shows newest entry per family,
- options sheet includes:
  - show all versions,
  - DEBUG retain-files toggle (Debug only).

Process screen:
- stage cards with three visual states:
  - pending,
  - active (accent-highlighted),
  - completed (green check state).
- active download stage shows:
  - percent above progress bar,
  - speed label and transfer,
  - inline manifest file list with status icons.

Summary screen:
- success / partial / failure card tones,
- metrics rows and detailed status section for failures or partial outcomes.

---

## 10. Error Handling and Partial Success

Rules:
- hard technical failures map to stage-specific downloader errors.
- if installer `.app` is created and moved but final cleanup fails:
  - session ends as partial success,
  - warning summary is shown instead of full hard-failure semantics.

User-facing messaging:
- permission/move failures are rewritten to clearer, action-oriented text,
- technical detail remains in logs.

---

## 11. DEBUG Behavior

Debug-only option:
- `DEBUG: Nie usuwaj pobranych plików`

When enabled:
- session files are retained after success/failure/cancel inside current app runtime.

When disabled:
- normal final cleanup stage executes.

Release:
- no DEBUG controls in downloader options UI.

---

## 12. Logging and Diagnostics

Downloader logs should include:
- discovery phase transitions and counts,
- manifest contents summary per item,
- verification step outputs (expected vs actual),
- helper assembly progress and movement logs,
- cleanup result and final destination status.

Logging category:
- downloader events are written via `AppLogging` with category `Downloader`.

---

## 13. File Structure

Downloader module:
- `macUSB/Features/Downloader/MacOSDownloaderCoordinator.swift`
- `macUSB/Features/Downloader/UI/MacOSDownloaderWindowShellView.swift`
- `macUSB/Features/Downloader/UI/MacOSDownloaderListView.swift`
- `macUSB/Features/Downloader/UI/MacOSDownloaderProcessView.swift`
- `macUSB/Features/Downloader/UI/MacOSDownloaderSummaryView.swift`
- `macUSB/Features/Downloader/Logic/MacOSDiscoveryLogic.swift`
- `macUSB/Features/Downloader/Logic/MacOSDownloadLogic.swift`
- `macUSB/Features/Downloader/Logic/MacOSVerificationLogic.swift`
- `macUSB/Features/Downloader/Logic/MacOSAssemblyLogic.swift`
- `macUSB/Features/Downloader/Logic/MacOSCleanupLogic.swift`

Helper touchpoints:
- `macUSB/Shared/Services/Helper/HelperIPC.swift`
- `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift`
- `macUSBHelper/IPC/HelperIPC.swift`
- `macUSBHelper/Service/PrivilegedHelperService.swift`
- `macUSBHelper/DownloaderAssembly/DownloaderAssemblyExecutor.swift`
- `macUSBHelper/DownloaderAssembly/DownloaderAssemblyProcess.swift`

---

## 14. Cross-Feature Safety Checklist

Before changing downloader:
- [ ] Confirm no USB workflow files are in scope.
- [ ] Confirm no analysis detection files are in scope.
- [ ] Confirm helper IPC changes are downloader-specific.

After changing downloader:
- [ ] Debug build succeeds.
- [ ] Downloader discovery + process + summary work as expected.
- [ ] USB creation flow still works unchanged.
- [ ] Analysis flow still works unchanged.

---

## 15. How to Extend Beyond Monterey

Extension strategy for additional families:
1. Keep common pipeline structure:
   connection -> download -> verify -> assembly -> cleanup -> summary.
2. Add per-family manifest/build compatibility rules as isolated policy.
3. Reuse helper assembly/cleanup transport and result mapping.
4. Keep stage keys and UI stage order stable unless explicitly redesigned.
5. Preserve cross-feature isolation and verify USB/analysis parity after each extension.
