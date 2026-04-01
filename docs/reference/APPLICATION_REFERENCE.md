# macUSB Application Reference

This document is the single reference for how the application behaves at runtime.

It is intentionally separated from process rules:
- Process/workflow/commit/changelog rules for agents are in `docs/AGENTS.md`.
- `docs/AGENTS.md` also contains a concise set of critical runtime invariants for day-to-day agent work.
- Runtime/product behavior is in `docs/reference/*`.

## Table of Contents
1. [Purpose and Scope](#1-purpose-and-scope)
2. [Runtime Prerequisites (Permissions/Background/FDA)](#2-runtime-prerequisites-permissionsbackgroundfda)
3. [End-to-End User Flow](#3-end-to-end-user-flow)
4. [UI/UX Contract](#4-uiux-contract)
5. [System Detection and Compatibility Matrix](#5-system-detection-and-compatibility-matrix)
6. [USB Capacity and Validation Rules](#6-usb-capacity-and-validation-rules)
7. [Installer Workflows](#7-installer-workflows)
8. [Privileged Helper Architecture and Invariants](#8-privileged-helper-architecture-and-invariants)
9. [Localization Runtime Contract](#9-localization-runtime-contract)
10. [Logging and Diagnostics Contract](#10-logging-and-diagnostics-contract)
11. [Notifications Contract](#11-notifications-contract)
12. [DEBUG Contract](#12-debug-contract)
13. [File Reference](#13-file-reference)
14. [Delicate Areas / Known Risks](#14-delicate-areas--known-risks)

---

## 1. Purpose and Scope

`macUSB` is a macOS app used to create bootable macOS/OS X/Mac OS X installer media from `.dmg`, `.iso`, `.cdr`, and `.app` sources.

Primary goals:
- detect installer type/version and route to correct workflow,
- safely prepare target USB media,
- run privileged operations through a helper path,
- keep the user flow guided and non-technical.

---

## 2. Runtime Prerequisites (Permissions/Background/FDA)

### Contract (MUST)
- The app requires both:
- `Full Disk Access` for `macUSB`,
- `Allow in the Background` approval for helper operation.
- Startup flow must keep checking and surfacing missing prerequisites.

### Current Behavior (AS-IS)
- Full Disk Access is verified on startup and surfaced via startup alert when missing.
- Helper background approval is checked at startup and in helper readiness paths.
- Missing permissions are shown in UI warnings and can block reliable helper execution.

### Update Trigger
Update this section when startup permission order, permission prompts, or permission gating behavior changes.

---

## 3. End-to-End User Flow

### Contract (MUST)
- Main flow remains:
- `WelcomeView` -> `SystemAnalysisView` -> `UniversalInstallationView` -> `CreationProgressView` -> `FinishUSBView`.
- Destructive operations require explicit confirmation.

### Current Behavior (AS-IS)
- User chooses installer source, analysis resolves compatibility flags, then user selects target USB.
- Summary screen confirms destructive start.
- Progress screen reflects helper-driven stages.
- Finish screen reports success/failure/cancel and final cleanup status.
- Tools menu includes `Download macOS installer...`, which opens a dedicated downloader sheet.
- Entering the downloader sheet triggers on-demand discovery (not app startup discovery) of officially available macOS/OS X installers from Apple endpoints.
- During discovery, downloader keeps the systems-list header visible and shows an inline progress panel (in the list area) with cancel action; options stay visible but disabled until scanning completes, then the panel transitions out and grouped installer entries are shown.
- Production download flow is currently enabled for selected `macOS Monterey` entries: preflight fetches real package manifest and sizes, then downloader runs sequential download, verification, helper-based `.app` assembly, and summary.
- Download artifacts are staged in `macUSB_temp/downloads/<session_id>` and final installer is moved to `~/Desktop/macUSB Downloads` with collision suffixing (`(2)`, `(3)`, ...).
- In `DEBUG` builds, downloader options include `DEBUG: Nie usuwaj pobranych plikow`; when enabled, session files are retained after success/failure/cancel until application shutdown cleanup.
- Application termination performs final cleanup of `macUSB_temp` to avoid leaving temporary downloader artifacts across sessions.

### Update Trigger
Update this section when screen order, navigation model, or gating transitions change.

---

## 4. UI/UX Contract

### Contract (MUST)
- Flow screens use fixed `550 x 750` window assumptions.
- Bottom action zones must use `BottomActionBar` with `safeAreaInset(edge: .bottom)`.
- Surfaces and CTAs must use compatibility wrappers from `LiquidGlassCompatibility.swift`:
- `macUSBPanelSurface`, `macUSBDockedBarSurface`, `macUSBPrimaryButtonStyle`, `macUSBSecondaryButtonStyle`.
- Concentric spacing/radii must come from `MacUSBDesignTokens`.
- `DEBUG` UI must not appear in `Release` builds.

### Current Behavior (AS-IS)
- UI uses semantic status cards (`StatusCard`) and shared design tokens.
- Sonoma/Sequoia use fallback visual layers; Tahoe uses glass-enabled wrappers.
- Main warnings include destructive erase confirmation and cancellation risk messaging.

### Update Trigger
Update when component primitives, token rules, core screen contracts, or cross-version visual behavior changes.

---

## 5. System Detection and Compatibility Matrix

### Contract (MUST)
- Analysis flags are the source of truth for install path selection.
- Unsupported detections must be surfaced clearly and block unsupported paths.

### Current Behavior (AS-IS)
- Detection supports modern, legacy, restore-legacy, PPC, Sierra-specific, Catalina, and Mavericks cases.
- Panther is explicitly unsupported.
- PPC-related flows are enabled for Tiger/Leopard/Snow Leopard pathways.
- For `.cdr` and `.iso`, when the selected source image is already mounted manually in macOS, analysis is blocked and a system alert instructs the user to unmount the image and run analysis again.

### Update Trigger
Update when compatibility rules, detection heuristics, or version mapping logic changes.

---

## 6. USB Capacity and Validation Rules

### Contract (MUST)
- Minimum USB requirement is dynamic and tied to detected installer generation.
- Before recognition is complete, requirement text is unresolved (`-- GB`) in UI.
- Proceed action remains blocked unless selected media passes capacity validation.
- APFS-selected targets must block proceed and require manual reformat in Disk Utility before continuing.

### Current Behavior (AS-IS)
- Sonoma (`14`) and older: UI requirement `16 GB`, technical threshold `15_000_000_000` bytes.
- Sequoia (`15`) and newer (including Tahoe): UI requirement `32 GB`, technical threshold `28_000_000_000` bytes.
- Capacity validation runs against mounted volume total capacity and updates error/warning cards accordingly.
- When an APFS target is selected, the app shows an inline error card, keeps proceed disabled, and presents a system alert with a direct action to open Disk Utility for manual reformat.

### Update Trigger
Update when threshold bytes, generation split rules, or capacity-related UI messaging behavior changes.

---

## 7. Installer Workflows

### Contract (MUST)
- Start path requires explicit destructive confirmation.
- Workflow selection must respect analyzed flags and selected source type.
- Temp cleanup ownership and fallback behavior must remain deterministic.

### Current Behavior (AS-IS)
- Standard path uses `createinstallmedia` family behavior.
- Legacy restore and Mavericks flows use restore-style pipelines.
- PPC flow uses dedicated PPC format/restore behavior.
- Catalina and Sierra use dedicated handling paths where required.
- Helper owns main temp staging/cleanup; finish screen provides fallback safety cleanup.

### Update Trigger
Update when workflow branching, stage sequence semantics, or flow-specific handling changes.

---

## 8. Privileged Helper Architecture and Invariants

### Contract (MUST)
- Privileged install operations must run via `SMAppService` + LaunchDaemon helper (no terminal fallback path).
- App/helper naming, mach service, listener, and plist wiring must stay aligned.
- App and helper signing compatibility must remain coherent across configs.
- Helper progress must remain observable in app state; live tool output remains diagnostic (not user-stage UI content).

### Current Behavior (AS-IS)
- Helper readiness/registration/repair and XPC health checks are centralized in helper services.
- Tools -> `Napraw helpera` always executes a hard reset sequence: `unregister`, short delay, explicit check that old helper no longer responds over XPC, then `register`, short delay, and final XPC health validation.
- Hard repair uses a base `3s` post-unregister stabilization delay; if helper still appears unchanged after that wait, it applies an additional one-time `5s` delay before continuing teardown validation.
- Hard repair uses bounded retry/backoff for transient registration and post-register XPC readiness failures (for example short-lived service invalidation races), while still failing explicitly when helper does not converge to a healthy state.
- App composes typed helper requests and maps helper events to stage progress.
- Helper executes stage pipelines, emits progress, and handles cancellation/failure shaping.
- Release operation expects app location and signing constraints to be satisfied.

### Update Trigger
Update when helper packaging, XPC contracts, stage model, signing matrix, or readiness lifecycle behavior changes.

---

## 9. Localization Runtime Contract

### Contract (MUST)
- Source language is Polish (`pl`) in `Localizable.xcstrings`.
- New UI copy must be authored in Polish first.
- Runtime non-`Text` user-facing strings must use `String(localized:)`.
- Helper localization keys and extraction anchors must remain synchronized.
- Supported languages set must stay coherent across runtime behavior and catalog.

### Current Behavior (AS-IS)
- SwiftUI `Text("...")` literals are used as localization keys for many static UI strings.
- Dynamic labels and formatted runtime strings use localized format keys.
- Helper stage/status rendering uses app-side localization key presentation.

### Update Trigger
Update when source-language policy, translation pipeline behavior, or supported language set changes.

---

## 10. Logging and Diagnostics Contract

### Contract (MUST)
- Important runtime logs should go through `AppLogging` APIs.
- Logs must stay human-readable and support diagnostics export.
- Helper live output is diagnostic data and should remain exported under helper log categories.

### Current Behavior (AS-IS)
- App logs startup milestones, stage transitions, info/error categories, and process duration.
- In-memory log buffering supports export.
- USB context logging includes metadata used for support diagnostics.

### Update Trigger
Update when logging categories, formatting conventions, export behavior, or observability scope changes.

---

## 11. Notifications Contract

### Contract (MUST)
- Notification permission prompting remains user-initiated from menu when status is not determined.
- Delivery depends on both system authorization and app-level toggle.
- Finish-screen background notification behavior must remain gated by app activity/state rules.

### Current Behavior (AS-IS)
- Menu notification state and toggle are centralized in `NotificationPermissionManager` and `MenuState`.
- Blocked/denied states route users to system settings via deep-link/fallback logic.
- Completion notifications are emitted only when inactive and policy allows.

### Update Trigger
Update when permission prompts, menu behavior, delivery gates, or notification content policy changes.

---

## 12. DEBUG Contract

### Contract (MUST)
- `DEBUG` menu/actions exist only for `#if DEBUG` builds.
- `Release` builds must not expose debug menu behavior.
- Debug routing must stay deterministic and avoid side effects on production state.

### Current Behavior (AS-IS)
- Debug menu provides Big Sur/Tiger summary shortcuts and temp-folder action.
- Root-level debug navigation uses delayed task and route-reset behavior.
- Debug routes use isolated temp paths and safe mount handling behavior.

### Update Trigger
Update when debug menu actions, debug route payloads, or debug safety constraints change.

---

## 13. File Reference

Core docs:
- `docs/reference/APPLICATION_REFERENCE.md` — runtime behavior contract.
- `docs/reference/CHANGELOG.md` — release notes for shipped versions.
- `docs/AGENTS.md` — end-to-end process, commit rules, and release-note rules for AI agents.

Core runtime areas:
- `macUSB/Features/Analysis/*` — source analysis and USB selection behavior.
- `macUSB/Features/Downloader/*` — downloader module split into `UI/*` (window shell + list/process/summary views), `Logic/*` (discovery + production Monterey download/verify/assembly/cleanup), and `MacOSDownloaderCoordinator.swift` (window lifecycle/orchestration entry).
- `macUSB/Features/Installation/*` — summary/start/progress orchestration.
- `macUSB/Features/Finish/*` — result behavior and fallback cleanup UX.
- `macUSB/Shared/Services/Helper/*` and `macUSBHelper/main.swift` — helper integration and privileged execution.
- `macUSB/Resources/Localizable.xcstrings` — localization catalog.

Downloader includes production runtime behavior for Monterey download flow; USB creation and analysis contracts remain untouched.

File relationships and responsibilities should remain consistent with runtime contracts above.

---

## 14. Delicate Areas / Known Risks

- Version/compatibility detection has many special cases; changes can affect multiple workflows.
- USB formatting/target resolution and APFS-to-physical-store mapping are high-risk paths.
- Helper registration/signing/environment issues can appear healthy in one stage and fail later if invariants drift.
- Localization key drift between helper emissions and app-side presentation breaks runtime text quality.
- Notification and permission UX can regress if startup/menu/finish logic diverges.

Keep this section current with real operational risk areas discovered during maintenance.
