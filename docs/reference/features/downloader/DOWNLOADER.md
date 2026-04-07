# macUSB Downloader Reference

This document describes the runtime behavior, UI contract, and technical pipeline of the macUSB downloader module.

Scope note:
- This file is focused on downloader behavior only.
- Process/commit rules are in `docs/AGENTS.md`.
- Global runtime documentation map is in `docs/reference/README.md`.

## Table of Contents
1. [Purpose and Scope](#1-purpose-and-scope)
2. [Top Rules and Invariants](#2-top-rules-and-invariants)
3. [Architecture Overview](#3-architecture-overview)
4. [Data Model and State](#4-data-model-and-state)
5. [Discovery Flow (Apple Catalog)](#5-discovery-flow-apple-catalog)
6. [Production Download Flow (Catalina to Tahoe)](#6-production-download-flow-catalina-to-tahoe)
7. [Verification Strategy](#7-verification-strategy)
8. [Helper Integration](#8-helper-integration)
9. [UI Contract](#9-ui-contract)
10. [Error Handling and Partial Success](#10-error-handling-and-partial-success)
11. [DEBUG Behavior](#11-debug-behavior)
12. [Logging and Diagnostics](#12-logging-and-diagnostics)
13. [File Structure](#13-file-structure)
14. [Cross-Feature Safety Checklist](#14-cross-feature-safety-checklist)
15. [How to Extend Beyond Current Scope](#15-how-to-extend-beyond-current-scope)

---

## 1. Purpose and Scope

Downloader provides:
- official macOS/OS X installer discovery from Apple sources,
- staged download/verify/build flow,
- final installer `.app` creation and target placement,
- deterministic temp cleanup and end-state summary.

Current production scope:
- full download pipeline is enabled for selected Catalina, Big Sur, Monterey, Ventura, Sonoma, Sequoia, and Tahoe entries,
- full download pipeline is enabled for Sierra and older official Apple Support installers distributed as `.dmg`,
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
  - `Modern` assembly and final privileged cleanup over XPC.

Runtime orchestration:
- `MacOSDownloaderWindowShellView` owns:
  - `MacOSDownloaderLogic` for discovery,
  - `MontereyDownloadFlowModel` for staged download pipeline (Catalina through Tahoe scope).

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

Discovery pipeline (`MacOSCatalogService`, orchestrated by `MacOSDownloaderLogic`):
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

## 6. Production Download Flow (Sierra and Older + Catalina to Tahoe)

Production pipeline (`MontereyDownloadFlowModel`) uses two compatible distribution modes:
- `Modern`: Big Sur, Monterey, Ventura, Sonoma, Sequoia, Tahoe (`InstallAssistant.pkg -> .app`).
- `Legacy`: High Sierra, Mojave, Catalina (`InstallAssistantAuto.pkg` + `RecoveryHDMetaDmg.pkg` + `InstallESDDmg.pkg`).
- `Oldest`: Sierra and older Apple Support downloads (`.dmg -> .pkg -> .app`).

Both modes share the same staged UI and runtime skeleton:
1. Connection / preflight
  - fetch real manifest for selected supported entry,
  - validate temporary disk capacity against 250% of total expected installer bytes.
2. Sequential file download
  - one file at a time,
  - progress %, speed sampling, transferred bytes text,
  - staged under `macUSB_temp/downloads/<session_id>/payload`.
3. File verification
  - size validation for each file,
  - IntegrityData/chunklist verification when available,
  - package signature verification (`pkgutil`) for downloaded `.pkg` files.
4. Installer build and move
  - `Legacy`: in-app assembly (without root) using `pkgutil --expand-full` + `hdiutil attach` and SharedSupport composition,
  - `Modern`: helper-based `InstallAssistant.pkg -> .app` plus final reassignment of installer `.app` ownership to the requesting user before cleanup,
  - `Oldest`: mount `.dmg`, extract installer `.pkg`, expand package (`pkgutil --expand`), extract `Payload` (`cpio` with compression fallback), and move final `.app` to `/Applications`,
  - final installer is placed in `/Applications`.
5. Final cleanup
  - dedicated helper-side cleanup of session temp directory,
  - executed as last stage before summary.

Power management contract during production download flow:
- idle sleep is blocked for the full runtime of one download session,
- activation starts when download workflow starts (`running` state),
- release is guaranteed on every terminal path: success, failure, or cancellation.

Summary:
- shows transfer, average speed, duration, and output file name,
- exposes Finder shortcut that reveals and selects the created installer `.app` when available (fallback: open destination folder),
- includes destination path and temporary-files cleanup status in dedicated summary rows.

---

## 7. Verification Strategy

Per-file verification order:
1. local presence and exact size check,
2. for `Oldest` (`10.7` to `10.12`) `.dmg` payloads: verify reference SHA-256 from `DownloadChecksums.json`,
3. for `Oldest` (`10.7` to `10.12`) `.dmg` payloads: mount image and verify embedded `.pkg` signature (`pkgutil --check-signature`),
4. for non-`Oldest` payloads: package signature check (`pkgutil`) for `.pkg` files,
5. for non-`Oldest` payloads: IntegrityData chunklist validation (`SHA-256` per chunk) when available.
6. High Sierra (`10.13`) fallback: when `IntegrityDataURL` is missing for legacy payloads (`InstallAssistantAuto.pkg`, `RecoveryHDMetaDmg.pkg`, `InstallESDDmg.pkg`), verify per-file SHA-256 against references from `DownloadChecksums.json`.

`Oldest` specific rule:
- for `.dmg` installers in `10.7` to `10.12`, the verification flow intentionally stops after reference SHA-256 and embedded package-signature validation (no IntegrityData checks).
- this `Oldest` flow is separate and not affected by `Modern/Legacy` verification rules.

Legacy exception:
- for OS X Lion (10.7) and OS X Mountain Lion (10.8), expired-but-Apple-signed package certificates are accepted for `.dmg` embedded installer packages.

Design intent:
- strict integrity for downloaded payload via file size + IntegrityData where available,
- package-signature confirmation for package payloads,
- no final `.app` build validation step.

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
- build installer `.app` from `InstallAssistant.pkg` for `Modern` workflow,
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
  - inline manifest file list with status icons,
  - verification stage text in state form (`Weryfikowanie pliku …`).
- close confirmation alert is shown only during active running download; summary close action is immediate.

Summary screen:
- success / partial / failure card tones,
- metrics rows and detailed status section for failures or partial outcomes,
- `Pokaż w Finderze` reveals and selects the created installer `.app` when available; otherwise opens `/Applications`.
- when an expired-but-trusted Apple package signature is accepted (currently Lion/Mountain Lion path), summary shows an additional neutral informational card with `info` icon explaining that signature trust is valid for this legacy case.

---

## 10. Error Handling and Partial Success

Rules:
- hard technical failures map to stage-specific downloader errors.
- if installer `.app` is created and moved but final cleanup fails:
  - session ends as partial success,
  - warning summary is shown instead of full hard-failure semantics.

User-facing messaging:
- permission/move failures are rewritten to clearer, action-oriented text,
- insufficient disk space during preflight is shown as a system `NSAlert` with required minimum and available space values,
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
- `macUSB/Features/Downloader/Logic/Discovery/*`
- `macUSB/Features/Downloader/Logic/Download/*`
- `macUSB/Features/Downloader/Logic/MacOSVerificationLogic.swift`
- `macUSB/Features/Downloader/Logic/Assembly/*`
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

## 15. How to Extend Beyond Current Scope

Extension strategy for additional families:
1. Keep common pipeline structure:
   connection -> download -> verify -> assembly -> cleanup -> summary.
2. Add per-family manifest/build compatibility rules as isolated policy.
3. Reuse helper assembly/cleanup transport and result mapping.
4. Keep stage keys and UI stage order stable unless explicitly redesigned.
5. Preserve cross-feature isolation and verify USB/analysis parity after each extension.
