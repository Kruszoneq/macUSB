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
11. [Complete File Reference (Every File)](#complete-file-reference-every-file)
12. [File Relationships (Who Calls What)](#file-relationships-who-calls-what)
13. [Contributor Rules and Patterns](#contributor-rules-and-patterns)
14. [Potential Redundancies and Delicate Areas](#potential-redundancies-and-delicate-areas)
15. [Notifications Chapter](#15-notifications-chapter)
16. [DEBUG Chapter](#16-debug-chapter)

---

## 1. Purpose and Scope
`macUSB` is a macOS app that turns a modern Mac (Apple Silicon or Intel) into a “service machine” for creating bootable macOS/OS X/Mac OS X USB installers. It streamlines a process that otherwise requires manual Terminal commands and legacy compatibility fixes.

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
3. Installer creation → app prepares and launches a Terminal script to do privileged operations.
4. Finish screen → cleanup, success/failure feedback, optional PPC instructions.

Main UI screens (in order):
- `WelcomeView` → `SystemAnalysisView` → `UniversalInstallationView` → `FinishUSBView`

Debug-only shortcut:
- In `DEBUG` builds, the app shows a top-level `DEBUG` menu in the system menu bar.
- `DEBUG` → `Przejdź do podsumowania (Big Sur) (2s delay)` triggers a simulated success path for `macOS Big Sur 11` and navigates to `FinishUSBView` after a 2-second delay.
- `DEBUG` → `Przejdź do podsumowania (Tiger) (2s delay)` triggers a simulated success path for `Mac OS X Tiger 10.4` with `isPPC = true` and navigates to `FinishUSBView` after a 2-second delay.
Detailed contract is documented in [Section 16](#16-debug-chapter).

Startup permissions flow:
- After the optional update alert on the Welcome screen, the app may show a notification-permission prompt.
- The update alert shows both remote available version and currently running app version.
Detailed notification behavior is documented in [Section 15](#15-notifications-chapter).

Fixed window size:
- 550 × 750, non-resizable.

---

## 3. Architecture and Key Concepts
The project is a SwiftUI macOS app with a pragmatic separation of views, logic extensions, services, and models.

Key concepts:
- SwiftUI + AppKit integration: menus, NSAlert dialogs, window configuration, and Terminal launching use AppKit APIs.
- View logic split: `UniversalInstallationView` UI lives in one file; its heavy logic lives in `CreatorLogic.swift` as an extension to keep type-checker complexity manageable.
- State-driven UI: extensive use of `@State`, `@StateObject`, `@EnvironmentObject` and `@Published` to bind logic to UI.
- NotificationCenter: used for flow resets, special-case actions (Tiger Multi-DVD override), and debug-only routing shortcuts.
- Notification permissions are centrally handled by `NotificationPermissionManager` (startup prompt, menu toggle, and system settings redirection).
- System analysis: reads `Info.plist` from the installer app inside a mounted image or `.app` bundle.
- USB detection: enumerates mounted external volumes; optionally includes external HDD/SSD with a user option; detects USB speed, partition scheme, filesystem format, and computes the `needsFormatting` flag for later stages.
- Terminal script execution: a shell script is written to a temporary folder, then opened in Terminal to run with `sudo`.

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
Frequently used SF Symbols in screens and menus include:
- `info.circle.fill`, `doc.badge.plus`, `internaldrive`, `checkmark.circle.fill`, `xmark.circle.fill`, `xmark.octagon.fill`, `exclamationmark.triangle.fill`, `externaldrive.fill`, `externaldrive.badge.xmark`, `applelogo`, `gearshape.2`, `clock`, `lock.fill`, `hand.raised.fill`, `terminal.fill`, `arrow.right`, `arrow.right.circle.fill`, `arrow.counterclockwise`, `xmark.circle`, `xmark.circle.fill`, `globe.europe.africa.fill`, `cup.and.saucer`, `square.and.arrow.down`, `arrow.triangle.2.circlepath`, `globe`, `chevron.left.forwardslash.chevron.right`.

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

Inputs and file selection:
- The file path field is a disabled `TextField` with `.roundedBorder`.
- Drag-and-drop target highlights with an accent-colored stroke (line width 3) and accent background at `0.1` opacity, with corner radius 12.

Progress indicators:
- Inline progress uses `ProgressView().controlSize(.small)` next to status text.
- Terminal-running and processing states show a dedicated panel with icon, title, subtitle, and progress indicator.

Welcome screen specifics:
- App icon is shown at 128 × 128.
- Description text is centered, uses `.title3`, and is padded horizontally.
- Start button is prominent, with `arrow.right` icon.

Finish screen specifics:
- Success/failure block uses green/red status panels.
- Cleanup section shows a blue panel with a trash icon while cleaning.
- Reset and exit buttons remain large, full-width, and prominent.
- If `FinishUSBView` appears while the app is inactive, the app sends a macOS system notification with success/failure result text only when both system permission and app-level notification toggle are enabled.

Formatting conventions:
- Bullet lists in UI are rendered as literal `Text("• ...")` lines, not as SwiftUI `List` or `Text` with markdown.
- Sections are separated by spacing rather than heavy borders; visual grouping is achieved by panels and background colors.

---

## 5. Localization and Language Rules (Polish as Source)
Source language is Polish. This is enforced in `Localizable.xcstrings` with `"sourceLanguage": "pl"`.

Practical rules:
- All new UI strings should be authored first in Polish.
- Use `Text("...")` with Polish strings; SwiftUI treats these as localization keys.
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
- For images (`.dmg`, `.iso`, `.cdr`): `hdiutil attach -plist -nobrowse -readonly`, then search mounted volume for `.app` and read `Info.plist`, with fallback to `SystemVersion.plist` for legacy systems.
- For `.app`: read `Contents/Info.plist` directly.

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
Implemented in: `UniversalInstallationView` (UI) + `CreatorLogic.swift` (logic)

### Standard Flow (createinstallmedia)
Used for most modern macOS installers.
- `createinstallmedia` is run in Terminal with `sudo`.
- If the selected drive has `needsFormatting == true` and flow is non-PPC, Terminal first formats the whole disk to `GPT + HFS+`, then continues to USB creation.
- In standard flow, preformatting runs after copy/patch/sign preparation steps and before `createinstallmedia`.
- After preformatting succeeds, Terminal is cleared and a fresh stage header is shown before USB creation starts.
- The effective target path is passed as `TARGET_USB_PATH` (updated after preformat mountpoint refresh).
- The app may copy the `.app` to a TEMP directory first when:
- the source is mounted from `/Volumes` (image), or
- Catalina requires post-processing, or
- codesign fixes are required.

### Legacy Restore Flow (Lion / Mountain Lion)
- Copies `InstallESD.dmg` to TEMP.
- Runs `asr imagescan` with admin privileges.
- If `needsFormatting == true` (non-PPC), a `GPT + HFS+` preformat stage runs in Terminal before restore.
- After preformatting succeeds, Terminal is cleared and a fresh stage header is shown before restore starts.
- Then `asr restore` runs to `TARGET_USB_PATH` (dynamic path after optional preformat).

### Mavericks Flow
- Copies the source image to TEMP.
- If `needsFormatting == true` (non-PPC), a `GPT + HFS+` preformat stage runs in Terminal before restore.
- Runs `asr imagescan`, then `asr restore` in Terminal (restore target resolved via `TARGET_USB_PATH`).

### PowerPC Flow
- Formats disk with `diskutil partitionDisk` using APM + HFS+.
- Uses `asr restore` to write the image to `/Volumes/PPC`.
- When `isPPC` is active, the drive flag `needsFormatting` is forced to `false` for installation context, because PPC formatting is already part of this flow.

### Sierra Special Handling
- Always copies `.app` to TEMP.
- Modifies `CFBundleShortVersionString` to `12.6.03`.
- Removes quarantine with `xattr`.
- Re-signs `createinstallmedia`.

### Catalina Special Handling
- Uses `createinstallmedia` first.
- Then replaces the installer app on the USB volume using `ditto`.
- Removes quarantine attributes on the target app.

### Terminal Monitoring Strategy
The app writes signal files to track progress:
- `terminal_running` → Terminal is active
- `terminal_done` → Terminal finished
- `terminal_success` → Operation succeeded
- `terminal_error` → Operation failed
- `auth_ok` → Admin authorization was granted
- `formatting_started` → GPT+HFS+ formatting stage has started (non-PPC preformat flow)
- `formatting_done` → GPT+HFS+ formatting stage completed and flow continues to USB creation
- `CreatorLogic` watches `formatting_started` / `formatting_done` and emits dedicated `AppLogging.stage(...)` markers for formatting start/end.

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

AppKit/Swift APIs:
- `NSAlert`, `NSOpenPanel`, `NSSavePanel`
- `NSWorkspace` (open URLs, launch Terminal scripts)
- `NSAppleScript` (admin privileges for commands)
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
- Formatting stage logs are emitted based on Terminal signal files (`formatting_started`, `formatting_done`) to mark start/end of preformatting.

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

## 11. Complete File Reference (Every File)
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
- `macUSB/macUSB.entitlements` — App entitlements (currently empty).
- `macUSB/Info.plist` — Bundle metadata and localization list.
- `macUSB/App/macUSBApp.swift` — App entry point, menus, AppDelegate behavior, and debug-only top-level `DEBUG` command menu.
- `macUSB/App/ContentView.swift` — Root view, window configuration, locale injection, and root-level debug navigation route handling.
- `macUSB/Features/Welcome/WelcomeView.swift` — Welcome screen and update check (update alert includes remote and current app version line).
- `macUSB/Features/Analysis/SystemAnalysisView.swift` — File/USB selection UI and navigation to install.
- `macUSB/Features/Analysis/AnalysisLogic.swift` — System detection and USB enumeration logic; propagates/logs USB metadata (speed, partition scheme, filesystem format, `needsFormatting`) and exposes `selectedDriveForInstallation` (PPC override of formatting flag).
- `macUSB/Features/Installation/UniversalInstallationView.swift` — Installer creation UI state and progress.
- `macUSB/Features/Installation/CreatorLogic.swift` — Installer creation logic and terminal scripting, including conditional non-PPC preformat (`GPT + HFS+`), formatting signal watchers, and staged terminal refresh between format/create phases.
- `macUSB/Features/Finish/FinishUSBView.swift` — Final screen, cleanup, sound feedback, background-result system notification (when app is inactive), and optional cleanup overrides used by debug simulation.
- `macUSB/Shared/Models/Models.swift` — `USBDrive` (including `needsFormatting`), `USBPortSpeed`, `PartitionScheme`, `FileSystemFormat`, and `SidebarItem` definitions.
- `macUSB/Shared/Models/Item.swift` — SwiftData model stub (currently unused).
- `macUSB/Shared/Services/LanguageManager.swift` — Language selection and locale handling.
- `macUSB/Shared/Services/MenuState.swift` — Shared menu state (skip analysis, external drives).
- `macUSB/Shared/Services/NotificationPermissionManager.swift` — Central notification permission and app-level toggle manager (startup prompt, menu action, system settings redirect).
- `macUSB/Shared/Services/UpdateChecker.swift` — Manual update checking.
- `macUSB/Shared/Services/Logging.swift` — Central logging and log export.
- `macUSB/Shared/Services/USBDriveLogic.swift` — USB volume enumeration plus metadata detection (speed, partition scheme, filesystem format).
- `macUSB/Resources/Localizable.xcstrings` — Localization catalog (source language: Polish).
- `macUSB/Resources/Assets.xcassets/Contents.json` — Asset catalog index.
- `macUSB/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` — Accent color definition.
- `macUSB/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` — App icon variants.
- `macUSB/Resources/Assets.xcassets/macUSB Icon/Contents.json` — “macUSB Icon” asset catalog.
- `macUSB/Resources/Assets.xcassets/macUSB Icon/Assets/Contents.json` — Sub-asset container metadata.
- `macUSB/Resources/Assets.xcassets/macUSB Icon/icon.dataset/Contents.json` — Icon dataset metadata.
- `macUSB/Resources/Assets.xcassets/macUSB Icon/icon.dataset/icon.json` — Icon JSON definition.
- `macUSB/macUSBIcon.icon/icon.json` — Original icon definition for the app icon source.

Notes on non-source items:
- `.DS_Store` files are Finder metadata and not used by the app.

---

## 12. File Relationships (Who Calls What)
This section lists the main call relationships and data flow.

- `macUSB/App/macUSBApp.swift` → uses `ContentView`, `MenuState`, `LanguageManager`, `UpdateChecker`, `NotificationPermissionManager`; in `DEBUG` also publishes `macUSBDebugGoToBigSurSummary` and `macUSBDebugGoToTigerSummary` from SwiftUI command menu actions.
- `macUSB/App/ContentView.swift` → presents `WelcomeView`, injects `LanguageManager`, calls `AppLogging.logAppStartupOnce()`, and maps debug notifications to delayed (2s) `FinishUSBView` routes (Big Sur and Tiger/PPC).
- `macUSB/Features/Welcome/WelcomeView.swift` → navigates to `SystemAnalysisView`, checks `version.json`, then triggers startup notification-permission flow.
- `macUSB/Features/Analysis/SystemAnalysisView.swift` → owns `AnalysisLogic`, calls its analysis and USB methods, updates `MenuState`, and forwards `selectedDriveForInstallation` to installation flow.
- `macUSB/Features/Analysis/AnalysisLogic.swift` → calls `USBDriveLogic`, uses `AppLogging`, mounts images via `hdiutil`; forwards USB metadata into selected-drive state.
- `macUSB/Features/Installation/UniversalInstallationView.swift` → displays install progress, calls logic in `CreatorLogic`, navigates to `FinishUSBView`.
- `macUSB/Features/Installation/CreatorLogic.swift` → uses `AppLogging`, logs selected USB metadata snapshot, conditionally preformats non-PPC drives, watches formatting signal files, writes Terminal scripts, runs privileged commands (AppleScript + sudo).
- `macUSB/Features/Finish/FinishUSBView.swift` → cleanup (unmount + delete temp), result sound, optional background system notification gated by permission/toggle, and reset callback.
- `macUSB/Shared/Services/LanguageManager.swift` → controls app locale, used by `ContentView` and menu.
- `macUSB/Shared/Services/MenuState.swift` → read/written by `macUSBApp.swift`, `SystemAnalysisView`, and `NotificationPermissionManager`.
- `macUSB/Shared/Services/NotificationPermissionManager.swift` → reads `UNUserNotificationCenter` state, updates `MenuState`, controls startup/menu alerts for notification permission, and opens system settings when blocked.
- `macUSB/Shared/Services/UpdateChecker.swift` → called from app menu.

---

## 13. Contributor Rules and Patterns
1. Polish-first localization: author new UI strings in Polish, then translate.
2. Do not add hidden behavior in the UI: show warnings for destructive operations.
3. Respect flow flags: `AnalysisLogic` flags are the source of truth for installation paths.
4. Keep the window fixed: UI assumes a 550×750 fixed layout.
5. Terminal operations must be observable: use marker files in TEMP for monitoring.
6. Use `AppLogging` for all important steps: keep logs helpful for diagnostics.
7. Avoid running privileged commands silently: use Terminal or AppleScript prompts.
8. Do not break the Tiger Multi-DVD override: menu option triggers a specific fallback flow.
9. Debug menu contract: top-level `DEBUG` menu is allowed only for `DEBUG` builds; it must not be available in `Release` builds.

---

## 14. Potential Redundancies and Delicate Areas
- Update checking is duplicated: `WelcomeView` and `UpdateChecker` both read `version.json`.
- Legacy detection and special cases are complex: changes in `AnalysisLogic` affect multiple installation paths.
- Localization: some Polish strings are hard-coded in `Text("...")`; ensure keys exist in `Localizable.xcstrings`.
- Cleanup logic is scattered: window close handlers, cancel flows, and finish view all attempt cleanup.

---

## 15. Notifications Chapter
This chapter defines notification permissions, UI toggles, and delivery rules.

Core components:
- `NotificationPermissionManager` is the source of truth for notification policy.
- `MenuState.notificationsEnabled` is the effective menu checkmark state.
- `WelcomeView` runs startup permission flow after optional update alert.
- `FinishUSBView` sends completion notification only when policy allows.

State model:
- System permission state comes from `UNUserNotificationCenter.getNotificationSettings()`.
- App-level toggle is stored in `UserDefaults` key `NotificationsEnabledInAppV1`.
- Startup prompt handling flag is stored in `UserDefaults` key `NotificationsStartupPromptHandledV1`.
- Effective enabled state (menu checkmark): `systemAuthorized && appEnabledInApp`.

System status interpretation (as implemented):
- Treated as authorized: `.authorized`, `.provisional`.
- Treated as blocked: `.denied`.
- Treated as undecided: `.notDetermined`.

Startup flow:
1. `WelcomeView.onAppear` runs `checkForUpdates(completion:)`.
2. After update flow completes (including alert close), app calls `NotificationPermissionManager.handleStartupFlowIfNeeded()`.
3. If system is authorized:
- Ensure app toggle default exists (`true` if missing).
- Mark startup prompt as handled.
4. If system is denied:
- Mark startup prompt as handled.
- Do not show startup prompt.
5. If system is not determined and startup prompt is not handled:
- Show custom alert:
- Title: `Czy chcesz włączyć powiadomienia?`
- Body: `Pozwoli to na otrzymanie informacji o zakończeniu procesu przygotowania nośnika instalacyjnego.`
- Buttons: primary `Włącz powiadomienia`, secondary `Nie teraz`
- For startup flow, any choice marks prompt as handled.

Menu behavior (`Opcje` → `Powiadomienia`):
- Checkmark source: `MenuState.notificationsEnabled`.
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
- `applicationDidFinishLaunching` and `applicationDidBecomeActive` both call `refreshState()` to keep menu checkmark aligned with real system state after returning from Settings.

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

## 16. DEBUG Chapter
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
