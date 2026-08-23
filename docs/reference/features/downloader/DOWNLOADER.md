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
6. [Production Download Flow (Catalina to Golden Gate)](#6-production-download-flow-catalina-to-golden-gate)
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
- full download pipeline is enabled for selected Catalina, Big Sur, Monterey, Ventura, Sonoma, Sequoia, Tahoe, and Golden Gate entries,
- full download pipeline is enabled for Sierra and older official Apple Support installers distributed as `.dmg`,
- discovery includes broad Apple-official stable entries across families,
- discovery always includes Apple Public Beta catalogs for the current macOS families supported by discovery, while beta entries remain hidden by default.

---

## 2. Top Rules and Invariants

- Do not modify USB creation logic while working on downloader.
- Do not modify analysis logic while working on downloader.
- Downloader network sources must stay Apple-official allowlisted endpoints.
- Discovery runs on entering downloader window, not at app startup.
- Downloader UI must remain stylistically aligned with app design system.
- Final cleanup stage must be explicit and ordered as the last stage before summary.
- The downloader window is a protected operation from presentation until full close, regardless of discovery, download, failure, cancellation, or summary state.
- Opening the downloader locks language changes for the current main flow.

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
  - `MontereyDownloadFlowModel` for staged download pipeline (Catalina through Golden Gate scope).

---

## 4. Data Model and State

Core models:
- `MacOSInstallerEntry`
  - identity, family, catalog name, version, build, source URL, optional product ID, release channel, source catalog URL, and the `isDownloaded` discovery snapshot.
- `MacOSInstallerReleaseChannel`
  - `stable` or `publicBeta`.
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
  - `connection`, `downloading`, `verifying`, `buildingInstaller`, `cleanup`.

---

## 5. Discovery Flow (Apple Catalog)

Discovery pipeline (`MacOSCatalogService`, orchestrated by `MacOSDownloaderLogic`):
1. On opening the downloader, inspect direct installer `.app` bundles in `/Applications` once and retain the resulting identities for the lifetime of that downloader window:
  - accept names beginning with `Install macOS`, `Install OS X`, or `Install Mac OS X`,
  - require a valid bundle plist and installer payload,
  - inspect each candidate sequentially outside the main thread,
  - mount only its own `SharedSupport.dmg` or `InstallESD.dmg` using read-only, no-browse, no-verify options,
  - read version/build metadata in order from MobileAsset, direct `SystemVersion.plist`, `OSInstall.mpkg/Distribution`, and a nested Finder-hidden `BaseSystem.dmg`,
  - check canonical metadata paths first and enumerate each mounted image at most once when fallbacks are needed,
  - treat failure of one metadata source as non-fatal and continue to the next independent source, while still propagating cancellation immediately,
  - detach nested images before parent images using a standard retry followed by forced detach,
  - report detach exhaustion as a discovery failure for that candidate and retain the temporary directory rather than removing an active mount point,
  - remove unique temporary mount and metadata-extraction directories only after all owned images are confirmed detached.
2. Download the stable Apple catalog and Public Beta catalogs for macOS 27, 26, and 15 from `swscan.apple.com` on every discovery.
3. Parse InstallAssistant candidates from products metadata.
4. Parse `.dist` metadata from Apple distribution hosts.
5. Treat the source catalog as the release-channel authority: entries from the stable catalog are stable, while entries unique to Public Beta catalogs are Public Beta regardless of prerelease wording in distribution metadata; when the same product ID is present in both channels, the stable catalog takes precedence.
6. Deduplicate by normalized identity within each release channel and across overlapping Public Beta catalogs.
7. Enrich legacy official entries from Apple Support list.
8. Probe installer sizes (catalog-prefill + network probe fallback).
9. Match the retained local installer identities to catalog entries by normalized exact version and build; when the catalog build is `N/A`, use exact version as the fallback.
10. Remove prerelease suffixes from family names so beta entries share the stable family section and icon; canonicalize Golden Gate entries under the `macOS Golden Gate` family.
11. Group by family and sort newest-first, with stable before Public Beta for equal builds.

Discovery UX contract:
- starts automatically on entering downloader window,
- always discovers stable and Public Beta entries together,
- starts with Public Beta visibility disabled whenever the downloader window is opened,
- changes to the beta visibility option immediately and smoothly refilter the retained discovery results while the options sheet remains open, without rerunning Apple catalog or local-installer discovery,
- manual refresh checks all stable and Public Beta catalogs while reusing the retained local-installer snapshot,
- inline progress panel is shown in list area,
- cancel is available during scanning,
- after completion panel transitions out and list appears,
- failure of any requested catalog uses the standard discovery failure screen without silently falling back to fewer channels.
- failure to enumerate `/Applications` is non-blocking and leaves the Apple list available without local badges,
- valid local installers absent from the active catalog are logged but do not affect the list,
- installer payloads whose version or build cannot be read are summarized in one app-icon alert, presented at most once per app runtime.

---

## 6. Production Download Flow (Sierra and Older + Catalina to Golden Gate)

Production pipeline (`MontereyDownloadFlowModel`) uses three compatible distribution modes:
- `Modern`: Big Sur, Monterey, Ventura, Sonoma, Sequoia, Tahoe, Golden Gate (`InstallAssistant.pkg -> .app`).
- `Legacy`: High Sierra, Mojave, Catalina (`InstallAssistantAuto.pkg` + `RecoveryHDMetaDmg.pkg` + `InstallESDDmg.pkg`).
- `Oldest`: Sierra and older Apple Support downloads (`.dmg -> .pkg -> .app`), with Yosemite/El Capitan/Sierra routed through helper-based `installer`.

Both modes share the same staged UI and runtime skeleton:
1. Connection / preflight
  - fetch the real manifest for the selected supported entry from the catalog URL retained during discovery,
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
  - `Oldest` (`10.10 Yosemite`, `10.11 El Capitan`, `10.12 Sierra`): helper mounts source `.dmg`, resolves embedded installer `.pkg`, installs with Apple `installer` on temporary writable HFS+ target using `CM_BUILD=CM_BUILD`, and copies final `.app` to `/Applications`,
  - `Oldest` (`10.7` to `10.9`): in-app path mounts `.dmg`, extracts installer `.pkg`, expands package (`pkgutil --expand`), extracts `Payload` (`cpio` with compression fallback), and moves final `.app` to `/Applications`,
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
- when final installer `.app` exists, exposes adjacent icon action that hands this `.app` path into analysis flow, triggers analysis automatically, and closes downloader window,
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
- build installer `.app` from Yosemite/El Capitan/Sierra `.dmg` by running Apple `installer` with `CM_BUILD=CM_BUILD` on helper-owned staging volume,
- perform final privileged cleanup of session temp directory.

App-side operation tracking:
- accepted assembly workflow IDs own a long-helper token through final result or XPC invalidation,
- final and fallback cleanup own cleanup tokens,
- privileged final cleanup also owns a nested long-helper token.

---

## 9. UI Contract

Window:
- fixed-width sheet from coordinator,
- app-like liquid/glass-compatible surfaces and tokens.
- can be opened from `Tools -> Pobierz instalator macOS...` and from the analysis screen button `Pobierz`.
- opening is blocked while USB creation flow is in operation screens (`UniversalInstallationView`, `CreationProgressView`, `FinishUSBView`), and the Tools menu item is disabled in those stages.
- the window-level active-operation token remains held across list, process, failure, cancellation, and summary UI until the window is fully closed.

List screen:
- grouped families,
- default mode hides Public Beta entries and shows the newest stable entry per family, plus every older stable entry detected in `/Applications`,
- enabling Public Beta visibility immediately adds the newest beta entry per family with an animated list transition, or every beta entry when `Pokaż wszystkie wersje` is also enabled, without rerunning discovery,
- overlapping Public Beta catalogs are deduplicated by system identity, version, and build,
- `Pokaż wszystkie wersje` shows every available stable version and, when beta visibility is enabled, every available Public Beta version,
- locally detected entries use a localized, accent-colored `POBRANY` badge in the selection list only,
- beta entries use a neutral `BETA` badge by default; the badge becomes accent-colored only in a selected list row and stays neutral in the active download view,
- on a physical Intel Mac, starting a download for Golden Gate or any newer system (major version `>= 27`) requires confirmation in an app-icon alert explaining that the installer can be downloaded and built, but cannot be used on that Mac to create bootable USB media,
- when the selected Golden Gate-or-newer entry is also marked as downloaded, the Intel compatibility warning is presented first; after confirmation, the existing redownload confirmation remains required,
- starting a download for an entry marked as downloaded requires confirmation in an app-icon alert; cancelling keeps the selection unchanged, while `Pobierz ponownie` starts the unchanged download workflow,
- options sheet includes:
  - show all versions,
  - show macOS Public Beta versions (session-only and off by default),
  - DEBUG retain-files toggle (Debug only).

Process screen:
- stage cards with three visual states:
  - pending,
  - active (accent-highlighted through the shared Liquid Glass-compatible active surface),
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
- when summary has a ready final `.app`, icon action next to Finder shortcut sends it to analysis and auto-runs analysis; if app is on Welcome screen, flow auto-navigates to analysis first.
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
- an unreadable local installer identity is reported in a non-blocking aggregate `NSAlert` after discovery,
- all local-installer alerts include the macUSB icon, localized title, localized description, and task-specific buttons,
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
- local installer candidates, ignored name-only matches, identities, catalog matches, and cleanup failures,
- active release channels and per-channel candidate/accepted counts,
- source channel and catalog URL used for manifest lookup,
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
  - `MacOSDiscoveryLocalInstallers.swift` orchestrates `/Applications` scanning, candidate validation, sequential identity reads, and catalog matching.
  - `MacOSLocalInstallerModels.swift` owns local identity normalization, exact version/build matching, and domain results/errors.
  - `MacOSLocalInstallerMetadataReader.swift` owns ordered metadata fallbacks and the single-pass mounted-image inventory.
  - `MacOSLocalInstallerLegacyParser.swift` extracts and parses legacy `OSInstall.mpkg/Distribution` metadata.
  - `MacOSLocalInstallerDiskImageManager.swift` owns unique mount points, reverse-order detach retries, and cleanup safety.
  - `MacOSLocalInstallerProcessRunner.swift` owns cancellable off-main process execution and concurrent diagnostic stream draining.
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
