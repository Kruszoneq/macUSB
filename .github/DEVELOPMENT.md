# macUSB Project Analysis and Contributor Guide

> This document is a comprehensive, English-language reference for the `macUSB` project.
> It is intended to give both AI agents and human contributors a complete, actionable understanding of:
> purpose, file responsibilities, file relationships, code conventions, operational rules, and runtime flow.
> This document is authoritative: every rule here matters. Any new solution or change introduced in the app must be recorded here.
>
> IMPORTANT RULE: **User-facing strings are authored in Polish by default.**
> Polish is the source language for localization and is the canonical base for new UI text.

## Table of Contents
1. [Purpose and Scope](#purpose-and-scope)
2. [High-Level App Flow](#high-level-app-flow)
3. [Architecture and Key Concepts](#architecture-and-key-concepts)
4. [Visual Requirements (UI/UX Contract)](#visual-requirements-uiux-contract)
5. [Localization and Language Rules (Polish as Source)](#localization-and-language-rules-polish-as-source)
6. [System Detection Logic (What the App Recognizes)](#system-detection-logic-what-the-app-recognizes)
7. [Installer Creation Flows](#installer-creation-flows)
8. [Operational Methods and External Tools Used](#operational-methods-and-external-tools-used)
9. [Persistent State and Settings](#persistent-state-and-settings)
10. [Logging and Diagnostics](#logging-and-diagnostics)
11. [Privileged Helper Deep-Dive (LaunchDaemon + XPC)](#11-privileged-helper-deep-dive-launchdaemon--xpc)
12. [Complete File Reference (Every File)](#12-complete-file-reference-every-file)
13. [File Relationships (Who Calls What)](#13-file-relationships-who-calls-what)
14. [Contributor Rules and Patterns](#14-contributor-rules-and-patterns)
15. [Potential Redundancies and Delicate Areas](#15-potential-redundancies-and-delicate-areas)
16. [Notifications Chapter](#16-notifications-chapter)
17. [DEBUG Chapter](#17-debug-chapter)

---

## 1. Purpose and Scope
`macUSB` is a macOS app that turns a modern Mac (Apple Silicon or Intel) into a “service machine” for creating bootable macOS/OS X/Mac OS X USB installers. It streamlines a process that otherwise requires manual privileged command-line operations and legacy compatibility fixes.

Core goals:
- Allow users to create bootable USB installers from `.dmg`, `.iso`, `.cdr`, or `.app` sources.
- Detect macOS/OS X version and choose the correct creation path.
- Automate legacy fixes (codesign, installer tweaks, asr restore) where needed.
- Support PowerPC-era USB creation flows.
- Provide a guided, non-technical UI and ensure safe handling (warnings, capacity checks).

---

## 2. High-Level App Flow
Navigation flow (SwiftUI):
1. Welcome screen → start button.
2. System analysis → user selects file, app analyzes it, then user selects a USB target.
3. Installer creation → app delegates the full write pipeline (source staging in TEMP, USB creation stages, and TEMP cleanup) to a LaunchDaemon helper via XPC.
4. Finish screen → success/failure feedback, optional PPC instructions, and fallback TEMP cleanup only if helper cleanup failed or was skipped.

Main UI screens (in order):
- `WelcomeView` → `SystemAnalysisView` → `UniversalInstallationView` → `FinishUSBView`

Debug-only shortcut:
- In `DEBUG` builds, the app shows a top-level `DEBUG` menu in the system menu bar.
- `DEBUG` → `Przejdź do podsumowania (Big Sur) (2s delay)` triggers a simulated success path for `macOS Big Sur 11` and navigates to `FinishUSBView` after a 2-second delay.
- `DEBUG` → `Przejdź do podsumowania (Tiger) (2s delay)` triggers a simulated success path for `Mac OS X Tiger 10.4` with `isPPC = true` and navigates to `FinishUSBView` after a 2-second delay.
Detailed contract is documented in [Section 17](#17-debug-chapter).

Startup permissions flow:
- After the optional update alert on the Welcome screen, the app may show a notification-permission prompt.
- The update alert shows both remote available version and currently running app version.
Detailed notification behavior is documented in [Section 16](#16-notifications-chapter).

Fixed window size:
- 550 × 750, non-resizable.

---

## 3. Architecture and Key Concepts
The project is a SwiftUI macOS app with a pragmatic separation of views, logic extensions, services, and models.

Key concepts:
- SwiftUI + AppKit integration: menus, NSAlert dialogs, and window configuration use AppKit APIs.
- View logic split: `UniversalInstallationView` UI lives in one file; its heavy logic lives in `CreatorLogic.swift` as an extension to keep type-checker complexity manageable.
- State-driven UI: extensive use of `@State`, `@StateObject`, `@EnvironmentObject` and `@Published` to bind logic to UI.
- NotificationCenter: used for flow resets, special-case actions (Tiger Multi-DVD override), and debug-only routing shortcuts.
- Notification permissions are centrally handled by `NotificationPermissionManager` (startup prompt, menu toggle, and system settings redirection).
- System analysis: reads `Info.plist` from the installer app inside a mounted image or `.app` bundle.
- USB detection: enumerates mounted external volumes; optionally includes external HDD/SSD with a user option; detects USB speed, partition scheme, filesystem format, and computes the `needsFormatting` flag for later stages.
- Privileged helper execution: a LaunchDaemon helper is registered via `SMAppService`, and privileged work is executed via typed XPC requests.
- Helper status UX has a healthy short-form alert (`Helper działa poprawnie`) with a system button to open full diagnostics.

---

## 4. Visual Requirements (UI/UX Contract)
Everything in this section is mandatory. If you introduce a new UI pattern, change an existing one, or add a new screen, you must update this file so it remains the single source of truth for visual rules.

Window and layout:
- Fixed window size is 550 × 750 on all screens.
- Window is non-resizable; min size and max size are fixed to 550 × 750.
- Window title is `macUSB`.
- Window zoom button is disabled; close and minimize remain enabled.
- Window is centered and uses `.fullScreenNone` and `.managed` behavior.
- Primary screens use a ScrollView for content with a sticky footer for actions and status panels.
- Navigation back buttons are hidden on key screens; navigation is driven by custom buttons and state.

Typography:
- Main screen titles use `.title` and `.bold()`.
- The Welcome screen title uses a custom system font size 40, weight bold.
- Section headers typically use `.headline`.
- Secondary text uses `.subheadline` and `.foregroundColor(.secondary)`.
- Small helper text uses `.caption` and `.secondary` color.

Iconography and sizes:
- SF Symbols are used throughout the UI.
- Informational panels use icons with `.font(.title2)` and a fixed width of 32.
- Major process/status blocks use `.font(.largeTitle)`.
Common status icons and their semantic colors:
- Success: `checkmark.circle.fill` in green.
- Error: `xmark.circle.fill` or `xmark.octagon.fill` in red.
- Warning: `exclamationmark.triangle.fill` in orange.
- Info: `info.circle.fill` in gray/secondary.
- USB: `externaldrive.fill` (blue/orange depending on state).
- In `SystemAnalysisView` success state, the app tries installer icons in this order: `Contents/Resources/ProductPageIcon.icns`, `Contents/Resources/InstallAssistant.icns`, then `Contents/Resources/Install Mac OS X.icns` (case-insensitive lookup). If none is found, fallback to `checkmark.circle.fill`.
- In `UniversalInstallationView` system info panel, the app shows detected installer icon (`detectedSystemIcon`) next to the system name; if unavailable, fallback is `applelogo`.
Frequently used SF Symbols in screens and menus include:
- `info.circle.fill`, `info.circle`, `doc.badge.plus`, `doc.text.magnifyingglass`, `internaldrive`, `checkmark.circle.fill`, `xmark.circle.fill`, `xmark.octagon.fill`, `exclamationmark.triangle.fill`, `externaldrive.fill`, `externaldrive`, `externaldrive.badge.plus`, `externaldrive.badge.xmark`, `applelogo`, `gearshape.2`, `gearshape`, `wrench.and.screwdriver`, `clock`, `lock.fill`, `arrow.right`, `arrow.right.circle.fill`, `arrow.counterclockwise`, `xmark.circle`, `xmark.circle.fill`, `globe.europe.africa.fill`, `cup.and.saucer`, `square.and.arrow.down`, `arrow.triangle.2.circlepath`, `globe`, `chevron.left.forwardslash.chevron.right`, `bell.slash`, `bell.and.waves.left.and.right`.

Panels and informational blocks:
- Most informational blocks are HStacks with icon left and text right.
- Standard padding is applied around panel content; corner radius is 8 (sometimes 10 for process panels).
- Color coding is consistent:
- Neutral info: `Color.gray.opacity(0.1)` (or `0.05` for subtle hints).
- Success: `Color.green.opacity(0.1)`.
- Warning: `Color.orange.opacity(0.1)`.
- Error: `Color.red.opacity(0.1)`.
- USB info: `Color.blue.opacity(0.1)`.
- Processing highlight: `Color.accentColor.opacity(0.1)`.
- Rollback/failure background: `Color.red.opacity(0.05)`.
- A `Divider()` separates the scrollable content from sticky footer actions.

Buttons:
- Primary actions use `.buttonStyle(.borderedProminent)` and `.controlSize(.large)`.
- Primary actions are tinted with `Color.accentColor` (or green for success).
- Secondary or cancel actions use `.tint(Color.gray.opacity(0.2))`.
- Full-width CTAs use `.frame(maxWidth: .infinity)` and padding around 8.
- Disabled actions reduce opacity to `0.5`.
- PPC instruction link uses `.buttonStyle(.bordered)` with `.controlSize(.regular)`.
- Buttons usually pair a text label with a right-side SF Symbol icon.

Alerts and dialogs:
- `NSAlert` uses the application icon and localized strings.
- Alerts are styled as informational or warning depending on action (updates, cancellations, external drive enablement, etc.).
- On startup helper bootstrap, if helper status is `requiresApproval` (Background Items permission missing), the app shows:
- title: `Wymagane narzędzie pomocnicze`
- message: `macUSB wymaga zezwolenia na działanie w tle, aby umożliwić zarządzanie nośnikami. Przejdź do ustawień systemowych, aby nadać wymagane uprawnienia`
- buttons: `Przejdź do ustawień systemowych` (opens Background Items settings via `SMAppService.openSystemSettingsLoginItems()`) and `Nie teraz`.
- This startup approval prompt is shown on every app launch while helper status remains `requiresApproval`.
- In first-run onboarding sequence it is shown before notification-permission prompts.
- Clicking `Rozpocznij` in `UniversalInstallationView` always shows a destructive-data warning alert before any helper workflow starts:
- title: `Ostrzeżenie o utracie danych`
- message: `Wszystkie dane na wybranym nośniku zostaną usunięte. Czy na pewno chcesz rozpocząć proces?`
- buttons: `Nie` (cancel start) and `Tak` (continue and start helper flow).
- Helper status check uses a two-step alert in healthy state:
- first alert: `Helper działa poprawnie` with system buttons `OK` (primary) and `Wyświetl szczegóły`.
- second alert (on details): full helper status report.
- Helper status check in `requiresApproval` state uses the same concise-first pattern:
- summary text: `macUSB wymaga zezwolenia na działanie w tle, aby umożliwić zarządzanie nośnikami. Przejdź do ustawień systemowych, aby nadać wymagane uprawnienia`
- buttons: `Przejdź do ustawień systemowych` (primary), `OK`, `Wyświetl szczegóły`.

Inputs and file selection:
- The file path field is a disabled `TextField` with `.roundedBorder`.
- Drag-and-drop target highlights with an accent-colored stroke (line width 3) and accent background at `0.1` opacity, with corner radius 12.

Screen headline copy:
- `SystemAnalysisView`: `Konfiguracja źródła i celu`
- `UniversalInstallationView`: `Szczegóły operacji`
- `FinishUSBView`: `Wynik operacji`

Menu icon mapping (current):
- `Opcje` → `Pomiń analizowanie pliku`: `doc.text.magnifyingglass`
- `Opcje` → `Włącz obsługę zewnętrznych dysków twardych`: `externaldrive.badge.plus`
- `Opcje` → `Język`: `globe`
- `Opcje` → notifications item uses dynamic label/icon:
- enabled: `Powiadomienia włączone` + `bell.and.waves.left.and.right`
- disabled: `Powiadomienia wyłączone` + `bell.slash`
- `Narzędzia` → `Otwórz Narzędzie dyskowe`: `externaldrive`
- `Narzędzia` → `Status helpera`: `info.circle`
- `Narzędzia` → `Napraw helpera`: `wrench.and.screwdriver`
- `Narzędzia` → `Ustawienia działania w tle…`: `gearshape` (same group as helper actions; no divider between `Napraw helpera` and settings action).

Progress indicators:
- Inline progress uses `ProgressView().controlSize(.small)` next to status text.
- During helper execution, the installation screen shows a dedicated progress panel with stage title, status text, and an indeterminate linear progress bar (without numeric percent).
- The same panel shows write speed (`MB/s`) on the right; during formatting stages it intentionally shows `- MB/s`.
- Live helper log lines are not rendered in UI; they are recorded into diagnostics logs for export.

Welcome screen specifics:
- App icon is shown at 128 × 128.
- Description text is centered, uses `.title3`, and is padded horizontally.
- Start button is prominent, with `arrow.right` icon.

Finish screen specifics:
- Success/failure block uses green/red status panels.
- Cleanup section shows a blue panel with a trash icon while cleaning.
- Reset and exit buttons remain large, full-width, and prominent.
- Success sound prefers bundled `burn_complete.aif` from app resources (with fallback to system sounds).
- If `FinishUSBView` appears while the app is inactive, the app sends a macOS system notification with success/failure result text only when both system permission and app-level notification toggle are enabled.

Formatting conventions:
- Bullet lists in UI are rendered as literal `Text("• ...")` lines, not as SwiftUI `List` or `Text` with markdown.
- Sections are separated by spacing rather than heavy borders; visual grouping is achieved by panels and background colors.

---

## 5. Localization and Language Rules (Polish as Source)
Source language is Polish. This is enforced in `Localizable.xcstrings` with `"sourceLanguage": "pl"`.

Practical rules:
- All new UI strings should be authored first in Polish.
- Terminology standard: in Polish user-facing copy use `nośnik USB` (not `dysk USB`) for consistency.
- Use `Text("...")` with Polish strings; SwiftUI treats these as localization keys.
- Helper stage/status keys sent from `macUSBHelper` are resolved dynamically at runtime in app (`localizedString(forKey:)`), so they are not auto-extracted from helper code; every new/changed helper key must be added manually to `Localizable.xcstrings`.
- To prevent helper keys from being marked as `Stale` in String Catalog, keep `HelperWorkflowLocalization.localizedValuesByKey` in `macUSB/Features/Installation/CreatorHelperLogic.swift` synchronized with helper-emitted keys.
Use `String(localized: "...")` when:
- The string is not a `Text` literal.
- The string is assigned to a variable before being shown.
- You want to force string extraction into the `.xcstrings` file.

Supported languages are defined in `LanguageManager.supportedLanguages`:
- `pl`, `en`, `de`, `ja`, `fr`, `es`, `pt-BR`, `zh-Hans`, `ru`

The language selection logic:
- `LanguageManager` stores the user’s selection in `selected_language_v2`.
- `auto` means: use system language if supported; otherwise fallback to English.
- The app requires a restart to fully update menu/localized system UI.

---

## 6. System Detection Logic (What the App Recognizes)
Analyzer: `AnalysisLogic` (used by `SystemAnalysisView`).

Files accepted:
- `.dmg`, `.iso`, `.cdr`, `.app`

Detection strategy:
- For images (`.dmg`, `.iso`, `.cdr`): `hdiutil attach -plist -nobrowse -readonly`, then for legacy media first check `Install Mac OS X` (folder) and `Install Mac OS X.app` for `Contents/Info.plist`; if not found, fallback to general `.app` scan and `Info.plist` read, with additional fallback to `SystemVersion.plist` for legacy systems.
- For `.app`: read `Contents/Info.plist` directly.
- During icon detection, analysis logs both the attempted `Contents/Resources` path and the exact `.icns` file path used when icon loading succeeds.

Key flags set by analysis:
- `isModern`: Big Sur and later (including Tahoe/Sequoia/Sonoma/Ventura/etc.)
- `isOldSupported`: Mojave / High Sierra
- `isLegacyDetected`: Yosemite / El Capitan
- `isRestoreLegacy`: Lion / Mountain Lion
- `isCatalina`: Catalina
- `isSierra`: supported only if installer version is `12.6.06`
- `isMavericks`: Mavericks
- `isPPC`: PowerPC-era flows (Tiger/Leopard/Snow Leopard; detected via version/name)
- `isUnsupportedSierra`: Sierra installer version is not `12.6.06`
- `showUnsupportedMessage`: used for UI warnings

Explicit unsupported case:
- Mac OS X Panther (10.3) triggers unsupported flow immediately.

---

## 7. Installer Creation Flows
Implemented in: `UniversalInstallationView` (UI) + `CreatorHelperLogic.swift` (workflow orchestration) + `CreatorLogic.swift` (shared helper-only utilities)

Start gating:
- The installation process cannot start immediately from the `Rozpocznij` button.
- A warning `NSAlert` confirms data loss on the selected USB target.
- Only explicit confirmation (`Tak`) proceeds to `startCreationProcessEntry()` and helper workflow initialization.

### Installation Summary Box Copy (`Przebieg procesu`)
The copy shown in the summary panel is intentionally simplified and differs by top-level flow flags:

When `isRestoreLegacy == true`:
- `• Obraz z systemem zostanie skopiowany i zweryfikowany`
- `• Nośnik USB zostanie sformatowany`
- `• Obraz systemu zostanie przywrócony`
- `• Pliki tymczasowe zostaną automatycznie usunięte`

When `isPPC == true`:
- `• Nośnik USB zostanie odpowiednio sformatowany`
- `• Obraz instalacyjny zostanie przywrócony`
- `• Pliki tymczasowe zostaną automatycznie usunięte`

Standard branch (`createinstallmedia` families):
- `• Pliki systemowe zostaną przygotowane`
- `• Nośnik USB zostanie sformatowany`
- `• Pliki instalacyjne zostaną skopiowane`
- `• Struktura instalatora zostanie sfinalizowana` (shown only when `isCatalina == true`)
- `• Pliki tymczasowe zostaną automatycznie usunięte`

### Standard Flow (createinstallmedia)
Used for most modern macOS installers.
- `createinstallmedia` is executed by the privileged helper (LaunchDaemon) using typed XPC requests.
- If the selected drive has `needsFormatting == true` and flow is non-PPC, helper first formats the whole disk to `GPT + HFS+`, then continues to USB creation.
- In standard flow, helper performs copy/patch/sign preparation steps first, then runs preformat (if needed), then `createinstallmedia`.
- The effective target path is resolved by helper (`TARGET_USB_PATH` equivalent), including mountpoint refresh after preformat.
- Source staging to TEMP is performed by helper (not app) when:
- the source is mounted from `/Volumes` (image), or
- Catalina requires post-processing, or
- codesign fixes are required.

### Legacy Restore Flow (Lion / Mountain Lion)
- Helper copies `InstallESD.dmg` to TEMP.
- Runs `asr imagescan` in helper context (root).
- If `needsFormatting == true` (non-PPC), a `GPT + HFS+` preformat stage runs in helper before restore.
- Then `asr restore` runs to helper-resolved target path after optional preformat.

### Mavericks Flow
- Helper copies the source image to TEMP.
- If `needsFormatting == true` (non-PPC), a `GPT + HFS+` preformat stage runs in helper before restore.
- Runs `asr imagescan`, then `asr restore` in helper (restore target resolved by helper).

### PowerPC Flow
- Formats disk with `diskutil partitionDisk` using APM + HFS+.
- Uses `asr restore` to write the image to `/Volumes/PPC`.
- When `isPPC` is active, the drive flag `needsFormatting` is forced to `false` for installation context, because PPC formatting is already part of this flow.
- Source selection for `asr --source` in PPC:
- For `.iso` / `.cdr`, helper request uses mounted source (`/Volumes/...`) to avoid UDIF format error (`-5351`).
- For other image types (e.g. `.dmg`), helper request uses staged image copy in temp (`macUSB_temp/PPC_*`).

### Sierra Special Handling
- Helper always copies `.app` to TEMP.
- Modifies `CFBundleShortVersionString` to `12.6.03`.
- Removes quarantine with `xattr`.
- Re-signs `createinstallmedia`.

### Catalina Special Handling
- Uses `createinstallmedia` first.
- Then helper replaces the installer app on the USB volume using `ditto`.
- Removes quarantine attributes on the target app.
- When Catalina transitions into the `ditto` stage, helper emits an explicit transition log line to `HelperLiveLog`.

### Cleanup Ownership
- TEMP cleanup (`macUSB_temp`) is executed by helper as the final operational step (best-effort, including failure/cancel paths).
- `FinishUSBView` keeps fallback cleanup as a safety net only when TEMP still exists.
- Mounting/unmounting the selected source image for analysis remains app-side and is not moved to helper.

### Helper Monitoring Strategy
The app tracks helper progress through XPC progress events:
- `stageKey`, `stageTitle`, `statusText`, `percent`, and optional `logLine`.
- UI localizes helper-provided stage/status keys through `Localizable.xcstrings` and shows them in an indeterminate progress panel (no numeric percent).
- Write speed (`MB/s`) is measured during active non-formatting helper stages and shown in the panel.
- During formatting stages (`preformat`, `ppc_format`) speed is hidden as `- MB/s`.
- `logLine` values are recorded to diagnostics logs under `HelperLiveLog` and are exportable.
- Live helper logs are not displayed in the installation UI.

---

## 8. Operational Methods and External Tools Used
The app relies on these macOS utilities and APIs.

Command-line tools:
- `hdiutil` (attach/detach, disk image mount handling)
- `asr` (imagescan, restore for legacy + Mavericks/PPC)
- `diskutil` (partitioning for PPC and non-PPC GPT+HFS+ preformat stage)
- `createinstallmedia` (installer creation)
- `codesign` (fixing installer signature for legacy/catalina)
- `xattr` (quarantine and extended attribute cleanup)
- `plutil` (modify Info.plist for Sierra)
- `ditto` (Catalina post-copy)
- `rm` (Catalina target app cleanup stage)

AppKit/Swift APIs:
- `NSAlert`, `NSOpenPanel`, `NSSavePanel`
- `NSWorkspace` (open URLs and system settings deep-links)
- `ServiceManagement` (`SMAppService`) for helper registration and state management
- `NSXPCConnection` / `NSXPCListener` for app↔helper IPC
- `IOKit` (USB device speed detection)
- `OSLog` (logging)

---

## 9. Persistent State and Settings
Stored in `UserDefaults`:
- `AllowExternalDrives`: whether external HDD/SSD are listed as targets.
- `selected_language_v2`: user’s preferred language (`auto` or fixed language).
- `AppleLanguages`: system override for app language selection.
- `DiagnosticsExportLastDirectory`: last folder used to export logs.
- `NotificationsStartupPromptHandledV1`: whether startup notification prompt has already been handled.
- `NotificationsEnabledInAppV1`: app-level toggle for notifications (independent from system permission).

Reset behavior:
- On app launch and termination, `AllowExternalDrives` is forced to `false` to avoid unsafe defaults.

---

## 10. Logging and Diagnostics
Central logging system: `AppLogging` in `Shared/Services/Logging.swift`.

Features:
- Startup “milestone” log with app version, macOS version, and hardware model.
- Stage markers via `AppLogging.stage()`.
- Category-based info/error logs with timestamps.
- In-memory buffer for exporting logs (max 5000 lines).
- Exportable from the app menu into a `.txt` file.
- Helper stdout/stderr lines are recorded under the `HelperLiveLog` category and included in diagnostics export.
- Finish stage logs total USB process duration (`MMm SSs` and total seconds) in `Installation` category.

### Log Message Requirements
The following requirements are mandatory for diagnostic logs:
- All application-authored diagnostic logs (existing and future) must be written in Polish.
- Keep logs human-readable first. Prefer descriptive labels over raw key/value fragments.
- For USB metadata, use explicit labels in messages, e.g. `Schemat: GPT, Format: HFS+`, instead of `scheme=GPT, fs=HFS+`.
- Keep boolean diagnostics readable for non-technical support checks (prefer `TAK` / `NIE` in Polish logs).
- PPC special case: when `isPPC` is active, do not log formatting-required as `TAK/NIE`; log `PPC, APM` instead.
- Keep critical USB context together in a single line when a target drive is selected or installation starts (device ID, capacity, USB standard, partition scheme, filesystem format, `needsFormatting` flag).
- Continue using categories (`USBSelection`, `Installation`, etc.) so exported logs are easy to filter.
- New logs must continue to go through `AppLogging` APIs (`info`, `error`, `stage`) to preserve timestamps and export behavior.

---

## 11. Privileged Helper Deep-Dive (LaunchDaemon + XPC)
This chapter defines the privileged helper architecture as currently implemented, including packaging, registration, XPC contracts, runtime behavior, UI integration, and failure handling.

### 11.1 Why the helper exists
- `macUSB` needs to run privileged operations (`diskutil`, `asr`, `createinstallmedia`, `xattr`, `ditto`, `plutil`, `codesign`, and cleanup steps) that cannot reliably run from a non-privileged app process.
- Installer creation runs via helper (`SMAppService` + LaunchDaemon + XPC) in both `Debug` and `Release`.
- The helper encapsulates privileged execution while keeping the app process focused on UI/state and user interaction.

### 11.2 Core helper components and ownership
- App-side orchestration:
- `macUSB/Shared/Services/Helper/HelperServiceManager.swift` handles helper registration, readiness checks, repair, removal, status dialogs, and approval/location gating.
- `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift` manages XPC connection lifecycle and start/cancel/health calls.
- `macUSB/Shared/Services/Helper/HelperIPC.swift` defines shared protocol and payload contracts.
- Installation workflow glue:
- `macUSB/Features/Installation/CreatorHelperLogic.swift` builds typed helper requests, starts workflow, maps progress to UI state, and handles cancellation/error routing.
- Helper target:
- `macUSBHelper/main.swift` hosts `NSXPCListener` and executes privileged workflow stages.
- LaunchDaemon definition:
- `macUSB/Resources/LaunchDaemons/com.kruszoneq.macusb.helper.plist` declares label, mach service, and helper binary location inside app bundle.

### 11.3 Bundle layout and Xcode packaging requirements
- The `macUSB` target has a target dependency on `macUSBHelper`.
- The `macUSB` target contains a Copy Files phase to:
- `Contents/Library/Helpers` for `macUSBHelper` binary.
- `Contents/Library/LaunchDaemons` for `com.kruszoneq.macusb.helper.plist`.
- LaunchDaemon plist currently contains:
- `Label = com.kruszoneq.macusb.helper`
- `MachServices` key `com.kruszoneq.macusb.helper = true`
- `BundleProgram = Contents/Library/Helpers/macUSBHelper`
- `AssociatedBundleIdentifiers` includes `com.kruszoneq.macUSB`
- `RunAtLoad = true`, `KeepAlive = false`
- Critical invariant: mach service and label naming must stay aligned across:
- `HelperServiceManager.machServiceName`
- LaunchDaemon plist `MachServices` and `Label`
- helper listener `NSXPCListener(machServiceName: ...)`

### 11.4 Signing, entitlements, and hardened runtime matrix
Current effective build configuration snapshot:
- App target (`macUSB`) Debug:
- `CODE_SIGN_STYLE = Automatic`
- `CODE_SIGN_IDENTITY = Apple Development`
- entitlements: `macUSB/macUSB.debug.entitlements`
- `ENABLE_HARDENED_RUNTIME = YES`
- App target (`macUSB`) Release:
- `CODE_SIGN_STYLE = Manual`
- `CODE_SIGN_IDENTITY = Developer ID Application`
- entitlements: `macUSB/macUSB.release.entitlements`
- `ENABLE_HARDENED_RUNTIME = YES`
- Helper target (`macUSBHelper`) Debug:
- `CODE_SIGN_STYLE = Automatic`
- `CODE_SIGN_IDENTITY = Apple Development`
- entitlements: `macUSBHelper/macUSBHelper.debug.entitlements`
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`
- `ENABLE_HARDENED_RUNTIME = YES`
- Helper target (`macUSBHelper`) Release:
- `CODE_SIGN_STYLE = Manual`
- `CODE_SIGN_IDENTITY = Developer ID Application`
- entitlements: `macUSBHelper/macUSBHelper.release.entitlements`
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`
- `ENABLE_HARDENED_RUNTIME = YES`
- Team ID is unified for both targets (`<TEAM_ID>` in this document; use your actual Apple Developer Team ID in project settings).
- Entitlements currently:
- app debug: Apple Events automation enabled, `get-task-allow = true`
- app release: Apple Events automation enabled, `get-task-allow = false`
- helper debug: `get-task-allow = true`
- helper release: `get-task-allow = false`
- Operational rule: app and helper must remain signed coherently (same Team ID and compatible signing mode per configuration) to avoid unstable registration and XPC trust failures.

### 11.5 Registration and readiness lifecycle (`HelperServiceManager`)
- Startup bootstrap:
- `bootstrapIfNeededAtStartup` runs from `WelcomeView` before notification startup flow.
- In normal path, it performs a non-interactive readiness check.
- If helper status is `requiresApproval`, startup approval alert is shown; startup completion reports not ready until user grants Background Items permission.
- In `DEBUG` when app runs from Xcode/DerivedData, bootstrap bypasses forced registration, but still checks `requiresApproval` and shows startup approval alert when needed.
- Installation gate:
- install flow calls interactive `ensureReadyForPrivilegedWork`.
- Before registration, location rule is evaluated:
- Release: app must be in `/Applications`.
- Debug: bypass is allowed when run from Xcode development build.
- Concurrency model:
- readiness checks are serialized in `coordinationQueue`.
- parallel callers are coalesced (`ensureInProgress`, pending completion queue).
- `SMAppService` status handling:
- `.enabled` → query XPC health; optionally recover if health fails.
- `.requiresApproval` → report failure; interactive flows show approval alert, and startup bootstrap also shows approval prompt before notification onboarding.
- `.notRegistered` / `.notFound` → perform `register()` then post-register validation.
- Registration failure nuances:
- if `register()` throws but status is `.enabled`, flow continues with validation.
- in Xcode sessions, `Operation not permitted` is handled specially and cross-checked via XPC health before hard-fail.
- Recovery path on health failure:
- reset local XPC connection,
- retry health check,
- if still broken: `unregister()` + short wait + `register()` + validation.

### 11.6 Status and repair UX behavior
- Status action:
- while status check is running, app shows a small floating panel with spinner (`Sprawdzanie statusu...`).
- if healthy: short alert `Helper działa poprawnie` with buttons `OK` and `Wyświetl szczegóły`.
- if unhealthy: one alert with full details (`Status usługi`, `Mach service`, app location, `XPC health`, `Szczegóły`).
- status details are fully localized through `Localizable.xcstrings` (labels and health state values), so detail alert content follows selected app language.
- Repair action:
- guarded against parallel repair runs (`repairInProgress`).
- opens a dedicated floating panel (`Naprawa helpera`) with:
- live textual progress lines (sourced from `HelperService` logs),
- spinner and status line,
- close button enabled only after completion.
- flow performs XPC reset and then full `ensureReadyForPrivilegedWork(interactive: true)`.
- Unregister action:
- directly calls `SMAppService.daemon(...).unregister()` and reports success/failure summary.

### 11.7 XPC transport contract and connection model
- Protocol methods (`PrivilegedHelperToolXPCProtocol`):
- `startWorkflow(requestData, reply)` returns `workflowID`.
- `cancelWorkflow(workflowID, reply)` requests cancellation.
- `queryHealth(reply)` confirms service responsiveness.
- Callback protocol (`PrivilegedHelperClientXPCProtocol`):
- `receiveProgressEvent(eventData)`
- `finishWorkflow(resultData)`
- Payload transport:
- JSON encoding/decoding via `HelperXPCCodec`.
- date encoding strategy: ISO8601.
- App connection:
- `NSXPCConnection(machServiceName: "com.kruszoneq.macusb.helper", options: .privileged)`
- exported object = `PrivilegedOperationClient` for helper callbacks.
- Timeout policy:
- workflow start reply timeout: 10s.
- default health query timeout: 5s.
- helper status dialog health timeout: 1.6s.
- Health detail normalization:
- helper daemon still returns raw health detail text.
- app-side `PrivilegedOperationClient` normalizes known health payload (`Helper odpowiada poprawnie (uid=..., euid=..., pid=...)`) into a localized string before rendering status details.
- XPC client-side failure messages used in status diagnostics (`Brak połączenia...`, `Timeout...`, invalidation/interruption, proxy/connection errors) are localized via string catalog keys.
- Connection fault behavior:
- interruption/invalidation clears handlers and emits synthetic workflow failure with stage `xpc_connection`.

### 11.8 App-side request assembly (`CreatorHelperLogic`)
- `startCreationProcessEntry()` always enters helper path.
- Before helper start:
- installation UI enters processing state and initializes progress (`Przygotowanie` / `Sprawdzanie gotowości helpera...`).
- `preflightTargetVolumeWriteAccess` probes write access on `/Volumes/*`; EPERM/EACCES produces explicit TCC-style guidance error.
- Workflow request payload includes:
- workflow kind (`standard`, `legacyRestore`, `mavericks`, `ppc`)
- source app path, optional original image path, temp work path, target paths, and BSD name
- target label
- flags (`needsPreformat`, `isCatalina`, `isSierra`, `needsCodesign`, `requiresApplicationPathArg`)
- `requesterUID = getuid()`
- App no longer performs copy/patch/sign staging in TEMP; helper owns those steps.
- UI mapping from helper events:
- stage title key, status key, and percent are updated from `HelperProgressEventPayload`, then localized in app using `Localizable.xcstrings`.
- `logLine` is not displayed in installer UI and is logged into diagnostics (`HelperLiveLog`).
- If workflow start fails with an IPC request-decode signature (invalid helper request), app performs one automatic helper reload (unregister/register) and retries workflow start once.

### 11.9 Helper-side workflow engine (`macUSBHelper/main.swift`)
- Service accepts only one active workflow at a time (rejects concurrent starts with code `409`).
- Executor model:
- helper performs a dedicated preparation stage first (staging to TEMP + required patch/sign tasks).
- main command stages are predefined per workflow kind with key/title/status/percent-range/executable/arguments.
- helper executes best-effort TEMP cleanup stage after success and also on failure/cancel paths.
- each stage emits start, streamed progress, and completion events.
- output parser:
- captures stdout+stderr line-by-line,
- extracts `%` tokens with regex and maps tool percentage into stage percentage range,
- keeps `statusText` as localized status key and forwards tool output as optional `logLine`.
- Command execution context:
- if `requesterUID > 0`, helper runs command as user via:
- `/bin/launchctl asuser <uid> <tool> ...`
- otherwise executes tool directly.
- Workflow specifics:
- non-PPC with `needsPreformat` adds `diskutil partitionDisk ... GPT HFS+ <targetLabel> 100%`.
- standard flow runs `createinstallmedia`, with optional Catalina cleanup/copy/xattr stages.
- Catalina copy (`ditto`) stage emits explicit transition log: createinstallmedia completed and flow is entering `ditto`.
- restore flows run `asr imagescan` + `asr restore`.
- PPC flow runs `diskutil ... APM HFS+ PPC 100%` then `asr restore` to `/Volumes/PPC`.
- Cancellation:
- `cancelWorkflow` triggers `Process.terminate()` and escalates to `SIGKILL` after 5s if needed.
- Error shaping:
- non-zero exit returns stage key, exit code, and last tool output line.
- helper adds an explicit hint when last line matches removable-volume permission failures (`operation not permitted` family).
- Health endpoint:
- `queryHealth` returns `Helper odpowiada poprawnie (uid=..., euid=..., pid=...)`.

### 11.10 Logging and observability for helper path
- `HelperService` category:
- registration/status/repair lifecycle diagnostics.
- `HelperLiveLog` category:
- streamed helper stdout/stderr (`logLine`) from command execution and decode failures (including Catalina transition to `ditto`).
- `Installation` category:
- user-facing operation milestones, helper workflow begin/end/fail events, and total process duration summary from finish screen.
- Export behavior:
- helper live logs are included in `AppLogging.exportedLogText()`.
- live log panel is intentionally not rendered on installation screen.

### 11.11 Common failure signatures and intended interpretation
- `requiresApproval`:
- helper is registered but blocked until user approval in system settings.
- `Operation not permitted` during register/re-register:
- often appears in Xcode-driven sessions; flow attempts health check fallback.
- `Helper jest włączony, ale XPC nie odpowiada` or timeout:
- service status is enabled, but app cannot complete query through XPC channel.
- `Could not validate sizes - Operacja nie jest dozwolona` from `asr`:
- tool-level permission/policy failure during restore validation stage.
- `Nie udało się zarejestrować helpera`:
- direct `SMAppService.register()` failure path (interactive alert shown).

### 11.12 Non-negotiable helper invariants
- Keep helper integration typed and centralized (do not introduce ad-hoc shell IPC paths).
- Keep privileged execution on helper path in all configurations; do not reintroduce terminal fallback.
- Preserve helper event fields (`stageTitle`, `statusText`, `percent`, `logLine`) and Polish user-facing messaging.
- Keep helper status UX two-step in healthy state (`OK` primary + `Wyświetl szczegóły`).
- Keep app bundle structure and plist placement exactly compatible with `SMAppService.daemon(plistName:)`.

### 11.13 Operational Checklists
Minimal runbook for day-to-day diagnostics and release safety:

- Diagnostics quick-check:
- Verify helper status from app menu (`Status helpera`): service enabled, location valid, `XPC health: OK`.
- Export diagnostics logs and confirm `HelperService`, `HelperLiveLog`, and `Installation` categories are present.
- For install failures, compare `failedStage`/`errorMessage` with helper stage stream and last tool output line.

- Signing/entitlements quick-check:
- App and helper must share the same Apple Team ID.
- `Debug`: both targets signed with `Apple Development`.
- `Release`: both targets signed with `Developer ID Application`, hardened runtime enabled.
- Entitlements files used by targets must match build config (`*.debug.entitlements` vs `*.release.entitlements`).

- Recovery/status quick-check:
- If service is enabled but XPC fails: run `Napraw helpera` (it resets client connection and re-validates registration).
- If status is `requiresApproval`: open system settings from helper alert and approve background item.
- You can manually open Background Items settings from `Narzędzia` → `Ustawienia działania w tle…`.

---

## 12. Complete File Reference (Every File)
Each entry below lists a file and its role. This section is exhaustive for tracked source and config files.

- `LICENSE.txt` — MIT license text.
- `README.md` — Public project overview, requirements, supported versions, languages.
- `version.json` — Remote version metadata for update checks.
- `screenshots/macUSBtheme.png` — UI preview image used by README.
- `screenshots/macUSBiconPNG.png` — App icon preview used by README.
- `.gitignore` — Git ignore rules.
- `.github/FUNDING.yml` — Funding/support metadata.
- `.github/PPC_BOOT_INSTRUCTIONS.md` — PowerPC Open Firmware USB boot guide.
- `.github/ISSUE_TEMPLATE/bug_report.yml` — Bug report template.
- `.github/ISSUE_TEMPLATE/feature_request.yml` — Feature request template.
- `macUSB.xcodeproj/project.pbxproj` — Xcode project definition (targets, build settings).
- `macUSB.xcodeproj/xcshareddata/xcschemes/macUSB.xcscheme` — Shared build scheme.
- `macUSB/macUSB.debug.entitlements` — App Debug entitlements.
- `macUSB/macUSB.release.entitlements` — App Release entitlements.
- `macUSB/Info.plist` — Bundle metadata and localization list.
- `macUSB/App/macUSBApp.swift` — App entry point, menus, AppDelegate behavior, and debug-only top-level `DEBUG` command menu.
- `macUSB/App/ContentView.swift` — Root view, window configuration, locale injection, and root-level debug navigation route handling.
- `macUSB/Features/Welcome/WelcomeView.swift` — Welcome screen and update check (update alert includes remote and current app version line).
- `macUSB/Features/Analysis/SystemAnalysisView.swift` — File/USB selection UI and navigation to install.
- `macUSB/Features/Analysis/AnalysisLogic.swift` — System detection and USB enumeration logic; propagates/logs USB metadata (speed, partition scheme, filesystem format, `needsFormatting`) and exposes `selectedDriveForInstallation` (PPC override of formatting flag).
- `macUSB/Features/Installation/UniversalInstallationView.swift` — Installer creation UI state, destructive start-confirmation trigger (`Rozpocznij`), helper progress panel (indeterminate bar + write speed), and handoff to finish screen with process start timestamp.
- `macUSB/Features/Installation/CreatorLogic.swift` — Shared installation utilities used by the helper path (start/cancel alerts, cleanup, monitoring).
- `macUSB/Features/Installation/CreatorHelperLogic.swift` — Primary installation path via privileged helper (SMAppService + XPC), helper progress mapping, and helper cancellation flow.
- `macUSB/Features/Finish/FinishUSBView.swift` — Final screen, fallback cleanup safety net (only if TEMP still exists), sound feedback, total process duration summary (`Ukończono w MMm SSs`), duration logging, background-result system notification (when app is inactive), and optional cleanup overrides used by debug simulation.
- `macUSB/Shared/Models/Models.swift` — `USBDrive` (including `needsFormatting`), `USBPortSpeed`, `PartitionScheme`, `FileSystemFormat`, and `SidebarItem` definitions.
- `macUSB/Shared/Models/Item.swift` — SwiftData model stub (currently unused).
- `macUSB/Shared/Services/LanguageManager.swift` — Language selection and locale handling.
- `macUSB/Shared/Services/MenuState.swift` — Shared menu state (skip analysis, external drives).
- `macUSB/Shared/Services/NotificationPermissionManager.swift` — Central notification permission and app-level toggle manager (startup prompt, menu action, system settings redirect).
- `macUSB/Shared/Services/Helper/HelperIPC.swift` — Shared app-side helper request/result/event payloads and XPC protocol contracts.
- `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift` — App-side XPC client for start/cancel/health checks and progress/result routing.
- `macUSB/Shared/Services/Helper/HelperServiceManager.swift` — Helper registration/repair/removal/status logic using `SMAppService`, including startup prompt when Background Items approval is required.
- `macUSB/Shared/Services/UpdateChecker.swift` — Manual update checking.
- `macUSB/Shared/Services/Logging.swift` — Central logging and log export.
- `macUSB/Shared/Services/USBDriveLogic.swift` — USB volume enumeration plus metadata detection (speed, partition scheme, filesystem format).
- `macUSB/Resources/Localizable.xcstrings` — Localization catalog (source language: Polish).
- `macUSB/Resources/Sounds/burn_complete.aif` — Bundled success sound used by `FinishUSBView`.
- `macUSB/Resources/Assets.xcassets/Contents.json` — Asset catalog index.
- `macUSB/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` — Accent color definition.
- `macUSB/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` — App icon variants.
- `macUSB/Resources/Assets.xcassets/macUSB Icon/Contents.json` — “macUSB Icon” asset catalog.
- `macUSB/Resources/Assets.xcassets/macUSB Icon/Assets/Contents.json` — Sub-asset container metadata.
- `macUSB/Resources/Assets.xcassets/macUSB Icon/icon.dataset/Contents.json` — Icon dataset metadata.
- `macUSB/Resources/Assets.xcassets/macUSB Icon/icon.dataset/icon.json` — Icon JSON definition.
- `macUSB/Resources/LaunchDaemons/com.kruszoneq.macusb.helper.plist` — LaunchDaemon definition embedded into the app bundle for SMAppService registration.
- `macUSB/macUSBIcon.icon/icon.json` — Original icon definition for the app icon source.
- `macUSBHelper/macUSBHelper.debug.entitlements` — Helper Debug entitlements.
- `macUSBHelper/macUSBHelper.release.entitlements` — Helper Release entitlements.
- `macUSBHelper/main.swift` — Privileged helper executable entry point (LaunchDaemon XPC listener and root workflow execution).

Notes on non-source items:
- `.DS_Store` files are Finder metadata and not used by the app.

---

## 13. File Relationships (Who Calls What)
This section lists the main call relationships and data flow.

- `macUSB/App/macUSBApp.swift` → uses `ContentView`, `MenuState`, `LanguageManager`, `UpdateChecker`, `NotificationPermissionManager`, `HelperServiceManager`; in `DEBUG` also publishes `macUSBDebugGoToBigSurSummary` and `macUSBDebugGoToTigerSummary` from SwiftUI command menu actions.
- `macUSB/App/ContentView.swift` → presents `WelcomeView`, injects `LanguageManager`, calls `AppLogging.logAppStartupOnce()`, and maps debug notifications to delayed (2s) `FinishUSBView` routes (Big Sur and Tiger/PPC).
- `macUSB/Features/Welcome/WelcomeView.swift` → navigates to `SystemAnalysisView`, checks `version.json`, bootstraps helper readiness via `HelperServiceManager`, then triggers startup notification-permission flow.
- `macUSB/Features/Analysis/SystemAnalysisView.swift` → owns `AnalysisLogic`, calls its analysis and USB methods, updates `MenuState`, and forwards `selectedDriveForInstallation` plus `detectedSystemIcon` to installation flow.
- `macUSB/Features/Analysis/AnalysisLogic.swift` → calls `USBDriveLogic`, uses `AppLogging`, mounts images via `hdiutil`; forwards USB metadata into selected-drive state.
- `macUSB/Features/Installation/UniversalInstallationView.swift` → displays install progress (stage/status with indeterminate bar and write speed), renders detected system icon in system info panel (with `applelogo` fallback), requires destructive confirmation before start, then starts the helper path via `startCreationProcessEntry()`, and navigates to `FinishUSBView` with process start timestamp.
- `macUSB/Features/Installation/CreatorHelperLogic.swift` → builds typed helper requests, coordinates helper execution/cancellation, and maps XPC progress events into UI state.
- `macUSB/Features/Installation/CreatorLogic.swift` → provides shared helper-path utilities (start/cancel alert flow, USB availability monitoring, emergency unmount, cleanup).
- `macUSB/Features/Finish/FinishUSBView.swift` → fallback cleanup safety net (unmount + conditional temp delete), result sound (prefers bundled `burn_complete.aif`), process duration summary/logging, optional background system notification gated by permission/toggle, and reset callback.
- `macUSB/Shared/Services/LanguageManager.swift` → controls app locale, used by `ContentView` and menu.
- `macUSB/Shared/Services/MenuState.swift` → read/written by `macUSBApp.swift`, `SystemAnalysisView`, and `NotificationPermissionManager`.
- `macUSB/Shared/Services/NotificationPermissionManager.swift` → reads `UNUserNotificationCenter` state, updates `MenuState`, controls startup/menu alerts for notification permission, and opens system settings when blocked.
- `macUSB/Shared/Services/Helper/HelperServiceManager.swift` → registers/repairs/removes LaunchDaemon helper via `SMAppService`, reports readiness, presents startup Background Items approval prompt when needed, and shows helper status alerts (healthy short-form + full details dialog).
- `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift` → app-side XPC client that starts/cancels helper workflows and logs `logLine` events to `HelperLiveLog`.
- `macUSB/Shared/Services/Helper/HelperIPC.swift` → helper IPC payload contracts (request, progress event, result).
- `macUSBHelper/main.swift` → helper-side XPC service, root workflow executor, progress event emitter, and cancellation handling.
- `macUSB/Shared/Services/UpdateChecker.swift` → called from app menu.

---

## 14. Contributor Rules and Patterns
1. Polish-first localization: author new UI strings in Polish, then translate.
2. Do not add hidden behavior in the UI: show warnings for destructive operations.
3. Respect flow flags: `AnalysisLogic` flags are the source of truth for installation paths.
4. Keep the window fixed: UI assumes a 550×750 fixed layout.
5. Privileged helper operations must be observable: keep stage/status/progress-state updates flowing to UI and keep `logLine` in diagnostics logs (`HelperLiveLog`) rather than screen panels.
6. Helper stage/status strings must stay localizable through `Localizable.xcstrings`; helper sends keys, app resolves localized text.
7. Use `AppLogging` for all important steps: keep logs helpful for diagnostics.
8. Privileged install flow must run through `SMAppService` + LaunchDaemon helper in all configurations (no terminal fallback).
9. Do not break the Tiger Multi-DVD override: menu option triggers a specific fallback flow.
10. Debug menu contract: top-level `DEBUG` menu is allowed only for `DEBUG` builds; it must not be available in `Release` builds.

---

## 15. Potential Redundancies and Delicate Areas
- Update checking is duplicated: `WelcomeView` and `UpdateChecker` both read `version.json`.
- Legacy detection and special cases are complex: changes in `AnalysisLogic` affect multiple installation paths.
- Localization: some Polish strings are hard-coded in `Text("...")`; ensure keys exist in `Localizable.xcstrings`.
- Cleanup logic still has multiple safety nets (helper final stage, cancel/window emergency paths, `FinishUSBView` fallback); preserve their non-destructive intent when refactoring.

---

## 16. Notifications Chapter
This chapter defines notification permissions, UI toggles, and delivery rules.

Core components:
- `NotificationPermissionManager` is the source of truth for notification policy.
- `MenuState.notificationsEnabled` is the effective notifications state used by menu label/icon.
- `WelcomeView` runs update check, then helper startup bootstrap, then notification startup flow.
- `FinishUSBView` sends completion notification only when policy allows.

State model:
- System permission state comes from `UNUserNotificationCenter.getNotificationSettings()`.
- App-level toggle is stored in `UserDefaults` key `NotificationsEnabledInAppV1`.
- Startup prompt handling flag is stored in `UserDefaults` key `NotificationsStartupPromptHandledV1`.
- Effective enabled state (menu label/icon): `systemAuthorized && appEnabledInApp`.

System status interpretation (as implemented):
- Treated as authorized: `.authorized`, `.provisional`.
- Treated as blocked: `.denied`.
- Treated as undecided: `.notDetermined`.

Startup flow:
1. `WelcomeView.onAppear` runs `checkForUpdates(completion:)`.
2. After update flow completes (including alert close), app calls `HelperServiceManager.bootstrapIfNeededAtStartup(...)`.
3. After helper startup bootstrap completion, app calls `NotificationPermissionManager.handleStartupFlowIfNeeded()`.
4. This ordering ensures helper approval alert (`requiresApproval`) is shown before notification onboarding prompt.
5. If system is authorized:
- Ensure app toggle default exists (`true` if missing).
- Mark startup prompt as handled.
6. If system is denied:
- Mark startup prompt as handled.
- Do not show startup prompt.
7. If system is not determined and startup prompt is not handled:
- Show custom alert:
- Title: `Czy chcesz włączyć powiadomienia?`
- Body: `Pozwoli to na otrzymanie informacji o zakończeniu procesu przygotowania nośnika instalacyjnego.`
- Buttons: primary `Włącz powiadomienia`, secondary `Nie teraz`
- For startup flow, any choice marks prompt as handled.

Menu behavior (`Opcje` → `Powiadomienia`):
- Menu state source: `MenuState.notificationsEnabled`.
- Dynamic label and icon:
- enabled: label `Powiadomienia włączone`, icon `bell.and.waves.left.and.right`
- disabled: label `Powiadomienia wyłączone`, icon `bell.slash`
- On tap, behavior depends on system status:
- Authorized/provisional: toggle app-level flag only (on/off in app), no redirection to system settings.
- Not determined: show enable prompt again (same as startup prompt), without reusing startup handled lock.
- Denied: show blocked alert:
- Title: `Powiadomienia są wyłączone`
- Body: `Powiadomienia dla macUSB zostały zablokowane w ustawieniach systemowych. Aby otrzymywać informacje o zakończeniu procesów, należy zezwolić aplikacji na ich wyświetlanie w systemie.`
- Buttons: primary `Przejdź do ustawień systemowych`, secondary `Nie teraz`

System settings redirection:
- First try deep-link:
- `x-apple.systempreferences:com.apple.preference.notifications?id=<bundleID>`
- Fallback:
- `x-apple.systempreferences:com.apple.preference.notifications`
- Final fallback: open System Settings app by bundle ID (`com.apple.systempreferences` or `com.apple.SystemSettings`).

Refresh rules:
- `applicationDidFinishLaunching` and `applicationDidBecomeActive` both call `refreshState()` to keep menu notification label/icon aligned with real system state after returning from Settings.

Finish screen delivery rules:
- `FinishUSBView.sendSystemNotificationIfInactive()` is called on appear.
- Notification is attempted only once per view instance (`didSendBackgroundNotification` guard).
- Notification is sent only when:
- App is inactive (`!NSApp.isActive`),
- System status is authorized/provisional,
- App-level toggle is enabled.
- Delivery check is centralized in `NotificationPermissionManager.shouldDeliverInAppNotification`.
- No automatic permission request is performed from `FinishUSBView`.

Completion notification content:
- Success:
- Title: `Instalator gotowy`
- Body: `Proces zapisu na nośniku zakończył się pomyślnie.`
- Failure:
- Title: `Wystąpił błąd`
- Body: `Proces tworzenia instalatora na wybranym nośniku zakończył się niepowodzeniem.`

Persistence and UX rules:
- `Nie teraz` in startup prompt suppresses only startup auto-prompt; user can still re-open permission prompt from menu when status is `.notDetermined`.
- App-level toggle persists across app restarts.
- Effective enablement always requires both system permission and app toggle.

---

## 17. DEBUG Chapter
This chapter defines the contract for debug-only shortcuts and behavior.

Scope:
- `DEBUG` functionality exists only when the app is compiled with `#if DEBUG`.
- In non-`DEBUG` builds (`Release`), the `DEBUG` menu and its actions must not be available.

Menu entry:
- Top-level menu name: `DEBUG`.
- Menu actions (localized labels):
- `Przejdź do podsumowania (Big Sur) (2s delay)`
- `Przejdź do podsumowania (Tiger) (2s delay)`

Action behavior:
- Both actions are immediate triggers that publish NotificationCenter events from `macUSBApp.swift`.
- Big Sur action publishes `macUSBDebugGoToBigSurSummary`.
- Tiger action publishes `macUSBDebugGoToTigerSummary`.

Navigation behavior (root-level):
- `ContentView` listens for both debug notifications.
- On each action, a delayed navigation task (`2s`) is scheduled.
- Existing pending debug task is canceled first, so only the last action executes.
- On execution, app resets to root flow (`macUSBResetToStart` + new `NavigationPath`) and pushes debug route to `FinishUSBView`.

Simulation payload:
- Big Sur route:
- `systemName = "macOS Big Sur 11"`
- `didFail = false`
- `isPPC = false`
- Tiger route:
- `systemName = "Mac OS X Tiger 10.4"`
- `didFail = false`
- `isPPC = true`

Safety constraints:
- Debug routes use isolated temp paths (`macUSB_debug_*`) and pass `shouldDetachMountPoint = false` to avoid side effects on real workflow mounts.
- Existing production flow (`UniversalInstallationView` → `FinishUSBView`) remains unchanged.

Rules:
- Do not expose debug actions to end users in `Release`.
- Keep debug navigation deterministic and side-effect-safe.

---

End of document.
