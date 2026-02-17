# macUSB Project Analysis and Contributor Guide

> This document is a comprehensive, English-language reference for the `macUSB` project.
> It is intended to give both AI agents and human contributors a complete, actionable understanding of:
> purpose, file responsibilities, file relationships, code conventions, operational rules, and runtime flow.
> This document is authoritative: every rule here matters. Any new solution or change introduced in the app must be recorded here.
>
> IMPORTANT RULE: **User-facing strings are authored in Polish by default.**
> Polish is the source language for localization and is the canonical base for new UI text.
>
> IMPORTANT RULE FOR AI AGENTS: Reading this document is mandatory, but not sufficient on its own.
> Before proposing or implementing changes, AI agents must also analyze the current codebase to build accurate runtime and architecture context.

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
3. Installation summary/start screen (`UniversalInstallationView`) → user reviews selected system/USB and confirms destructive start.
4. Creation progress (`CreationProgressView`) → app delegates the full write pipeline (source staging in TEMP, USB creation stages, and TEMP cleanup) to a LaunchDaemon helper via XPC and renders per-stage progress.
5. Finish screen → success/failure feedback, optional PPC instructions, and fallback TEMP cleanup only if helper cleanup failed or was skipped.

Main UI screens (in order):
- `WelcomeView` → `SystemAnalysisView` → `UniversalInstallationView` → `CreationProgressView` → `FinishUSBView`

Debug-only shortcut:
- In `DEBUG` builds, the app shows a top-level `DEBUG` menu in the system menu bar.
- `DEBUG` → `Przejdź do podsumowania (Big Sur) (2s delay)` triggers a simulated success path for `macOS Big Sur 11` and navigates to `FinishUSBView` after a 2-second delay.
- `DEBUG` → `Przejdź do podsumowania (Tiger) (2s delay)` triggers a simulated success path for `Mac OS X Tiger 10.4` with `isPPC = true` and navigates to `FinishUSBView` after a 2-second delay.
- `DEBUG` → `Otwórz macUSB_temp` opens `${TMPDIR}/macUSB_temp` in Finder; if folder does not exist, app shows an alert titled `Wybrany folder nie istnieje`.
- `DEBUG` menu footer contains informational rows: `Informacje` and live `Przekopiowane dane: xx.xGB`, refreshed every 2 seconds during helper workflow.
Detailed contract is documented in [Section 17](#17-debug-chapter).

Startup permissions flow:
- After the optional update alert on the Welcome screen, the app does not auto-prompt for notification permission.
- Notification permission prompt is user-initiated from `Opcje` → `Powiadomienia` when system status is `.notDetermined`.
- The update alert shows both remote available version and currently running app version.
Detailed notification behavior is documented in [Section 16](#16-notifications-chapter).

Fixed window size:
- 550 × 750, non-resizable.

---

## 3. Architecture and Key Concepts
The project is a SwiftUI macOS app with a pragmatic separation of views, logic extensions, services, and models.

Key concepts:
- SwiftUI + AppKit integration: menus, NSAlert dialogs, and window configuration use AppKit APIs.
- View logic split: `UniversalInstallationView` UI lives in one file; helper workflow orchestration is in `CreatorHelperLogic.swift`, while shared install utilities live in `CreatorLogic.swift`.
- State-driven UI: extensive use of `@State`, `@StateObject`, `@EnvironmentObject` and `@Published` to bind logic to UI.
- NotificationCenter: used for flow resets, special-case actions (Tiger Multi-DVD override), and debug-only routing shortcuts.
- Notification permissions are centrally handled by `NotificationPermissionManager` (default-off app toggle, menu-initiated prompt/toggle, and system settings redirection).
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
- Primary screens use a `ScrollView` for content and `safeAreaInset(edge: .bottom)` for action/status bars.
- Shared bottom action layer uses `BottomActionBar` (`macUSB/Shared/UI/BottomActionBar.swift`) and not ad-hoc `Divider + background` footers.
- Navigation back buttons are hidden on key screens; navigation is driven by custom buttons and state.

Toolbar-first chrome:
- Top-level flow screens use contextual `navigationTitle` in the native title/toolbar area:
- `WelcomeView`: `Start`
- `SystemAnalysisView`: `Konfiguracja źródła i celu`
- `UniversalInstallationView`: `Szczegóły operacji`
- `CreationProgressView`: `Tworzenie nośnika`
- `FinishUSBView`: `Wynik operacji`
- Do not duplicate these top-level screen titles as large in-content headings.
- Window toolbar style is unified compact and should stay system-driven.

Typography:
- Section headers use `.headline`.
- Secondary content uses `.subheadline` + `.foregroundColor(.secondary)`.
- Helper/detail text uses `.caption`.
- The Welcome screen renders `macUSB` under the app icon as a moderately emphasized title (visually larger than the subtitle, but not dominant like a page heading).

Design tokens and concentricity:
- Shared geometry tokens live in `macUSB/Shared/UI/DesignTokens.swift`.
- Use `MacUSBDesignTokens` values for window size, paddings, spacing, icon column width, and radii.
- Core spacing/scale tokens for flow screens:
- `contentSectionSpacing`, `sectionGroupSpacing`,
- `panelInnerPadding`, `statusCardCompactPadding`,
- `headlineScale(for:)`, `subheadlineScale(for:)`.
- Corner-radius hierarchy must remain concentric and predictable:
- standard panel radius from `panelCornerRadius(for:)`
- prominent panel radius from `prominentPanelCornerRadius(for:)`
- docked bottom bar top radius from `dockedBarTopCornerRadius(for:)`
- Docked bottom bar minimum height must use `dockedBarMinHeight`.
- Avoid arbitrary per-screen radii that break visual rhythm.

Panels, surfaces, and tinting:
- Shared compatibility wrappers live in `macUSB/Shared/UI/LiquidGlassCompatibility.swift`.
- Use `StatusCard` for status/info cards (`macUSB/Shared/UI/StatusCard.swift`), not repeated custom stacks.
- Use `macUSBPanelSurface` / `macUSBDockedBarSurface` instead of ad-hoc background stacks.
- Use `macUSBLowEmphasisPanelSurface` for low-emphasis helper panels when a softer structural layer is needed.
- Semantic surface tones are:
- `.neutral`, `.subtle` for structural grouping
- `.info`, `.success`, `.warning`, `.error`, `.active` for state meaning
- Strong tinting is reserved for semantic states; neutral containers stay subtle.
- Per screen, prefer one primary semantic status card and keep helper/instructional blocks neutral/subtle.
- Use spacing/layering for separation; do not add `Divider()` as a default panel separator.

Buttons:
- Primary CTA styling must go through `macUSBPrimaryButtonStyle(...)`.
- Secondary/cancel styling must go through `macUSBSecondaryButtonStyle(...)`.
- Full-width CTAs use `.frame(maxWidth: .infinity)` and `padding(8)`.
- Disabled actions use `.disabled(...)` and reduced opacity from shared style wrappers.
- Each screen should have one visually dominant primary action.
- PPC instruction link uses `.buttonStyle(.bordered)` with `.controlSize(.regular)`.
- In docked bottom bars, avoid a visual "double rounding" effect: bar radius is larger context, controls are visually subordinate.

Iconography:
- SF Symbols remain the default icon system.
- Panel icon column uses `MacUSBDesignTokens.iconColumnWidth` (32 pt).
- Keep toolbar/navigation icons mostly monochrome; use color to encode semantic state (success/warning/error/active) and primary CTA emphasis only.
- In `SystemAnalysisView` success state, the app tries installer icons in this order: `Contents/Resources/ProductPageIcon.icns`, `Contents/Resources/InstallAssistant.icns`, then `Contents/Resources/Install Mac OS X.icns` (case-insensitive lookup). If none is found, fallback to `checkmark.circle.fill`.
- In `UniversalInstallationView` and `CreationProgressView`, the system panel uses `detectedSystemIcon` when available; fallback is `applelogo`.

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
- Clicking `Przerwij` in `CreationProgressView` shows a dedicated cancellation warning:
- title: `Czy przerwać tworzenie nośnika?`
- message: `Nośnik USB nie będzie zdatny do rozruchu, jeśli proces zostanie zatrzymany przed zakończeniem. Konieczne będzie ponowne przygotowanie urządzenia.`
- buttons: `Kontynuuj` (primary, keeps process running) and `Przerwij` (cancels helper workflow and routes to finish with `Przerwano` status).
- Helper status check uses a two-step alert in healthy state:
- first alert: `Helper działa poprawnie` with system buttons `OK` (primary) and `Wyświetl szczegóły`.
- second alert (on details): full helper status report.
- Helper status check in `requiresApproval` state uses the same concise-first pattern:
- summary text: `macUSB wymaga zezwolenia na działanie w tle, aby umożliwić zarządzanie nośnikami. Przejdź do ustawień systemowych, aby nadać wymagane uprawnienia`
- buttons: `Przejdź do ustawień systemowych` (primary), `OK`, `Wyświetl szczegóły`.

Inputs and file selection:
- The file path field is a disabled `TextField` with `.roundedBorder`.
- Drag-and-drop target highlights with an accent-colored stroke (line width 3) and accent background at `0.1` opacity, with corner radius 12.

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
- During helper execution, `CreationProgressView` shows a stage list where:
- pending stages are subtle/low-emphasis cards (title + stage icon),
- the currently active stage is semantic active card (title + status + linear progress bar; for tracked copy stages it is determinate),
- completed stages are compact neutral cards with success icon accent.
- Catalina stage icon mapping in `CreationProgressView`: `catalina_cleanup` uses `doc.badge.gearshape` (file-structure adjustments), `catalina_copy` uses `doc.on.doc.fill`, `catalina_xattr` uses `checkmark.shield.fill`.
- Tracked copy stages (`restore`, `ppc_restore`, `createinstallmedia`, `catalina_copy`) show a numeric percent badge on the right side of active stage row.
- For tracked copy stages, the percent is derived from copied-data bytes against source-size bytes and is clamped to `99%` while the stage is still running; completion to `100%` is implied only by stage transition to completed state.
- For active USB-write stages (`restore`, `ppc_restore`, `createinstallmedia`, and Catalina `catalina_copy`/`ditto` stage), `CreationProgressView` shows write speed below the progress bar as `Szybkość zapisu: xx MB/s` (rounded integer, no decimals) in monospaced-digit secondary typography.
- Live helper log lines are not rendered in UI; they are recorded into diagnostics logs for export.
- Motion should stay short and semantic (state-change transitions such as fade/slide), without decorative animations.

Welcome screen specifics:
- App icon is shown at 128 × 128.
- App name `macUSB` is shown directly below the icon.
- Description text is centered, visually secondary, and scaled through `subheadlineScale(for:)` (not as a dominant heading).
- Welcome title scale is controlled through `headlineScale(for:)` and must remain clearly larger than subtitle without becoming page-header sized.
- Start button is prominent and uses shared primary style wrapper with `arrow.right` icon.

Finish screen specifics:
- Success/failure/cancelled state uses one primary semantic result panel (`Sukces!`, `Niepowodzenie!`, or `Przerwano`) plus a lighter summary panel.
- In success mode, the installer summary row uses detected system icon in the main left icon slot (instead of USB disk icon); fallback remains `externaldrive.fill` when icon is unavailable.
- Cleanup section is rendered inside the shared bottom action layer while cleaning.
- Reset and exit actions remain large and full-width; reset is secondary, exit is primary.
- Success sound prefers bundled `burn_complete.aif` from app resources (with fallback to system sounds).
- If `FinishUSBView` appears while the app is inactive, the app sends a macOS system notification with success/failure result text only when both system permission and app-level notification toggle are enabled.
- In cancelled mode (`Przerwano`), `FinishUSBView` intentionally does not play any result sound and does not send a background notification.

Formatting conventions:
- Bullet lists in UI are rendered as literal `Text("• ...")` lines, not as SwiftUI `List` or `Text` with markdown.
- Sections are separated by spacing and surfaces; avoid decorative separators unless semantically necessary.

### 4.1 Component Contract (Shared UI Primitives)
- `StatusCard` contract:
- `StatusCard(tone:cornerRadius:density:content:)` where `density` is `StatusCardDensity.regular` or `.compact`.
- Compact density is for helper/instructional/supporting blocks; regular density is for primary semantic blocks.
- `BottomActionBar` contract:
- bottom action zones in flow screens must use `BottomActionBar` with `safeAreaInset(edge: .bottom)`.
- `BottomActionBar` uses `macUSBDockedBarSurface` and fixed min height from tokens; do not recreate custom docked bar containers.
- Liquid Glass wrapper contract:
- all flow surfaces and CTAs must route through wrappers in `LiquidGlassCompatibility.swift` (`macUSBPanelSurface`, `macUSBLowEmphasisPanelSurface`, `macUSBDockedBarSurface`, `macUSBPrimaryButtonStyle`, `macUSBSecondaryButtonStyle`).
- Direct usage of 26-only glass APIs in feature views is not allowed.

### 4.2 Liquid Glass Compatibility Contract
- Compatibility mode helper:
- `VisualSystemMode` and `currentVisualMode()` in `macUSB/Shared/UI/LiquidGlassCompatibility.swift`.
- On macOS 26+ (Tahoe):
- Use native Liquid Glass APIs through wrappers (`glassEffect`, `glass`, `glassProminent`) for panels and button styles.
- Keep toolbar and window chrome system-driven; avoid custom painted titlebar backgrounds.
- On macOS 14/15 (Sonoma/Sequoia):
- Use fallback materials/colors/strokes from the same wrappers.
- Keep subtle panels lower-contrast than neutral panels (lighter fallback stroke/fill for `.subtle`).
- Preserve hierarchy, spacing, and action order; do not emulate Tahoe glass with custom heavy effects.
- Availability rules:
- Every 26-only API must be guarded with `if #available(macOS 26.0, *)`.
- App-level calls requiring newer APIs (for example toolbar background behaviors) must also be guarded.
- Deployment target remains `MACOSX_DEPLOYMENT_TARGET = 14.6`.
- UX consistency requirement:
- Functional hierarchy and interaction behavior must match across macOS 14/15/26 even if rendering differs per OS.

---

## 5. Localization and Language Rules (Polish as Source)
Source language is Polish. This is enforced in `Localizable.xcstrings` with `"sourceLanguage": "pl"`.

Practical rules:
- All new UI strings should be authored first in Polish.
- Terminology standard: in Polish user-facing copy use `nośnik USB` (not `dysk USB`) for consistency.
- Keep message style consistent with existing in-app forms; for progress/status copy prefer nominal process forms already used in the app (for example `Przygotowywanie...`, `Rozpoczynanie...`) instead of mixing with direct-action forms.
- Translations in `Localizable.xcstrings` must match the real UI context where the phrase appears (button, alert title, warning body, progress status, etc.); avoid overly literal translation when it harms clarity, tone, or UX.
- Immutable product slogan rule: the phrase `Tworzenie botoowalnych dysków USB z systemem macOS oraz OS X nigdy nie było takie proste` is the app’s official slogan and must remain unchanged verbatim in this exact form.
- Use `Text("...")` with Polish strings; SwiftUI treats these as localization keys.
- Helper sends stable technical localization keys (for example `helper.workflow.prepare_source.title`) in XPC progress events.
- Installation UI renders helper stage/status with `Text(LocalizedStringKey(...))`, so helper progress text follows app locale from SwiftUI environment.
- Non-`Text` runtime labels (for example speed/debug metrics text) must use `String(localized:)` with localized format keys (currently `Szybkość zapisu: %d MB/s`, `Szybkość zapisu: - MB/s`, and `Przekopiowane dane: %.1f GB`).
- Keep helper key anchors in `macUSB/Shared/Localization/HelperWorkflowLocalizationKeys.swift` (`HelperWorkflowLocalizationExtractionAnchors`) synchronized with emitted keys to keep String Catalog extraction stable.
- Every helper localization key must be translated in all supported app languages (`pl`, `en`, `de`, `ja`, `fr`, `es`, `pt-BR`, `zh-Hans`, `ru`).
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
Implemented in: `UniversalInstallationView` (summary/start UI) + `CreationProgressView` (runtime stage UI) + `CreatorHelperLogic.swift` (workflow orchestration) + `CreatorLogic.swift` (shared helper-only utilities)

Start gating:
- The installation process cannot start immediately from the `Rozpocznij` button.
- A warning `NSAlert` confirms data loss on the selected USB target.
- Only explicit confirmation (`Tak`) proceeds to helper workflow initialization.
- On `Tak`, navigation immediately moves to `CreationProgressView`, then helper startup continues in background.
- Before helper start, secondary action `Wróć` returns to `SystemAnalysisView` and preserves the currently selected source file and USB target.

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
- For APFS-selected targets, helper first resolves APFS container selection to physical whole-disk media (APFS physical store / parent whole disk) before running `partitionDisk`.
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
- Then helper performs three post stages with distinct UI titles:
- `catalina_cleanup` → title key `helper.workflow.catalina_cleanup.title` (`Przygotowanie struktury instalatora`),
- `catalina_copy` (`ditto`) → title key `helper.workflow.catalina_copy.title` (`Kopiowanie plików na nośnik instalacyjny`),
- `catalina_xattr` → title key `helper.workflow.catalina_xattr.title` (`Nadawanie uprawnień plikom instalatora`).
- Then helper replaces the installer app on the USB volume using `ditto`.
- Removes quarantine attributes on the target app.
- When Catalina transitions into the `ditto` stage, helper emits an explicit transition log line to `HelperLiveLog`.

### Cleanup Ownership
- TEMP cleanup (`macUSB_temp`) is executed by helper as the final operational step (best-effort, including failure/cancel paths).
- `FinishUSBView` keeps fallback cleanup as a safety net; if TEMP was already removed by helper (or vanishes in a race), fallback treats it as success and does not show false cleanup error.
- Mounting/unmounting the selected source image for analysis remains app-side and is not moved to helper.
- Helper stage `finalize` is technical-only and is intentionally not rendered in `CreationProgressView`.

### Helper Monitoring Strategy
The app tracks helper progress through XPC progress events:
- `stageKey`, `stageTitleKey`, `statusKey`, `percent`, and optional `logLine`.
- `CreationProgressView` localizes helper stage/status through `Localizable.xcstrings` and renders stage cards plus active-stage progress bar.
- Compatibility rule: app canonicalizes displayed helper title/status from `stageKey` when known, so older helper builds that still send raw phrases do not break localization.
- App-side transfer monitor computes source sizes (`restore` source image, `ppc_restore` source image file, `createinstallmedia` app bundle, Catalina `ditto` source app bundle), then estimates copied bytes every 2 seconds from measured write speed (`MB/s * elapsed`), and derives tracked stage percent from copied/total ratio.
- Transfer monitor follows helper-resolved target identity (`request.targetBSDName` resolved to whole-disk), not only the original UI drive snapshot, so speed sampling stays aligned after APFS/container remap or post-format remount changes.
- For `createinstallmedia`, estimation starts from the beginning of the stage (speed-based integration over elapsed time), independent of helper text output timing.
- Tracked stage percent in UI is clamped to `99%` while stage remains active; stage completion is represented by transition into completed card state.
- App-side transfer monitor has diagnostic fallback logging: after repeated missing speed samples, it emits `HelperLiveLog` entries with `stage`, requested BSD id, failure counter, speed snapshot, stage-percent snapshot, and copied/total bytes snapshot; on first successful sample after degraded period, it emits a recovery log.
- Write speed (`MB/s`) is measured during active non-formatting helper stages.
- In `CreationProgressView`, speed is rendered only for active USB-write stages (`restore`, `ppc_restore`, `createinstallmedia`, `catalina_copy`) in format `Szybkość zapisu: xx MB/s` with rounded integer values.
- Speed label is localized via `String(localized:)` format key (`Szybkość zapisu: %d MB/s`), and non-measured state uses localized `Szybkość zapisu: - MB/s`.
- During formatting stages (`preformat`, `ppc_format`) speed label is not displayed in UI (internal value remains `- MB/s`).
- During helper workflow, `MenuState` exposes debug copied-data label (`Przekopiowane dane: xx.xGB`) updated every 2 seconds.
- `logLine` values are recorded to diagnostics logs under `HelperLiveLog` and are exportable.
- Live helper logs are not displayed in installer UI.

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
- app initializes helper state (`Przygotowanie` / `Przygotowywanie operacji...`) and, after destructive confirmation, routes to `CreationProgressView`.
- `preflightTargetVolumeWriteAccess` probes write access on `/Volumes/*`; EPERM/EACCES produces explicit TCC-style guidance error.
- Workflow request payload includes:
- workflow kind (`standard`, `legacyRestore`, `mavericks`, `ppc`)
- source app path, optional original image path, temp work path, target paths, and target BSD name resolved to whole-disk media for formatting (including APFS volume/container to physical-store fallback)
- target label
- flags (`needsPreformat`, `isCatalina`, `isSierra`, `needsCodesign`, `requiresApplicationPathArg`)
- `requesterUID = getuid()`
- App no longer performs copy/patch/sign staging in TEMP; helper owns those steps.
- UI mapping from helper events:
- stage title key, status key, and percent are updated from `HelperProgressEventPayload`; app prefers canonical key mapping from `stageKey` for compatibility, then renders via `LocalizedStringKey` and `Localizable.xcstrings` in `CreationProgressView`.
- `logLine` is not displayed in installer UI and is logged into diagnostics (`HelperLiveLog`).
- If helper startup fails before active workflow, app automatically pops back from `CreationProgressView` to `UniversalInstallationView` and surfaces the error there.
- If workflow start fails with an IPC request-decode signature (invalid helper request), app performs one automatic helper reload (unregister/register) and retries workflow start once.

### 11.9 Helper-side workflow engine (`macUSBHelper/main.swift`)
- Service accepts only one active workflow at a time (rejects concurrent starts with code `409`).
- Executor model:
- helper performs a dedicated preparation stage first (staging to TEMP + required patch/sign tasks).
- main command stages are predefined per workflow kind with key/title/status/percent-range/executable/arguments.
- helper executes best-effort TEMP cleanup stage after success and also on failure/cancel paths.
- `FinishUSBView` fallback cleanup treats "already removed / no such file" temp race as non-error (no false `Błąd czyszczenia` when helper cleaned first).
- each stage emits start, streamed progress, and completion events.
- output parser:
- captures stdout+stderr line-by-line,
- treats both `\n` and `\r` as streamed line separators (important for interactive tool output such as `asr restore`),
- extracts standard `%` tokens and dotted `asr` progress markers (`....10....20...`) via regex, taking the latest token and mapping tool percentage into stage percentage range,
- for `createinstallmedia`, parser ignores `Erasing Disk` percent lines so erase-phase output does not artificially advance copy-stage progress,
- keeps `statusKey` as localized status key and forwards tool output as optional `logLine`.
- Command execution context:
- if `requesterUID > 0`, helper runs command as user via:
- `/bin/launchctl asuser <uid> <tool> ...`
- otherwise executes tool directly.
- Workflow specifics:
- non-PPC with `needsPreformat` adds `diskutil partitionDisk ... GPT HFS+ <targetLabel> 100%`.
- `preformat` / `ppc_format` resolve selected target (especially APFS container selections) to physical whole-disk device before `diskutil partitionDisk`.
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

### 11.9.1 Exact stage order and percent windows
- Global invariant:
- Every workflow starts with `prepare_source` (`0 → 10`).
- Every workflow runs `cleanup_temp` near the end (`>=99 → 100`, best-effort).
- Every workflow ends with `finalize` (`100`).
- Standard (`workflowKind = standard`):
- Optional `preformat` (`10 → 30`) when `needsPreformat == true` and non-PPC.
- `createinstallmedia`:
- with preformat: `30 → 98` (or `30 → 90` for Catalina),
- without preformat: `15 → 98` (or `15 → 90` for Catalina).
- Catalina post stages:
- `catalina_cleanup` (`90 → 94`), `catalina_copy` (`94 → 98`), `catalina_xattr` (`98 → 99`).
- Legacy restore (`workflowKind = legacyRestore`):
- Optional `preformat` (`10 → 30`) when `needsPreformat == true`.
- `imagescan`: `30 → 50` (with preformat) or `15 → 35` (without).
- `restore`: `50 → 98` (with preformat) or `35 → 98` (without).
- Mavericks (`workflowKind = mavericks`):
- Same stage timings as `legacyRestore`: optional `preformat`, then `imagescan`, then `restore`.
- PPC (`workflowKind = ppc`):
- `ppc_format` (`10 → 25`), then `ppc_restore` (`25 → 98`).

### 11.9.2 Exact source preparation and codesign rules (helper-owned)
- `prepare_source` executes in helper before command stages and selects effective source according to workflow:
- `legacyRestore`: copy `InstallESD.dmg` from selected `.app` to TEMP.
- `mavericks`: copy selected image to TEMP as `InstallESD.dmg`.
- `ppc`:
- `.iso/.cdr` + mounted source available: use mounted `/Volumes/...` source.
- other images: copy selected image to TEMP as `PPC_<filename>`.
- fallback: use mounted source if image path missing and mount exists.
- `standard`:
- Sierra: copy `.app` to TEMP, patch `CFBundleShortVersionString`, clear quarantine (`xattr -dr`), sign `createinstallmedia`.
- Catalina / `needsCodesign` / mounted source: copy `.app` to TEMP; for Catalina or `needsCodesign` run local codesign flow in helper.
- plain standard without these conditions: use original app path directly (no staging).
- Local codesign flow (`performLocalCodesign`) remains active in helper:
- clears attributes (`xattr -cr`) on staged app,
- signs key installer components and `createinstallmedia` (`codesign -s - -f`), with best-effort behavior per component (`failOnNonZeroExit = false`).

### 11.9.3 Helper localization and translation pipeline (exact behavior)
- Source of truth for helper localization IDs is `macUSB/Shared/Localization/HelperWorkflowLocalizationKeys.swift`.
- Exact translation path at runtime:
1. `macUSBHelper/main.swift` defines each workflow stage with technical keys (`titleKey`, `statusKey`) from `HelperWorkflowLocalizationKeys`.
2. Helper emits XPC progress event payload: `stageKey`, `stageTitleKey`, `statusKey`, `percent`, optional `logLine`.
3. `HelperProgressEventPayload` decoder (`macUSB/Shared/Services/Helper/HelperIPC.swift`) accepts both modern fields (`stageTitleKey`/`statusKey`) and legacy fields (`stageTitle`/`statusText`) for backward compatibility.
4. Decoder canonicalizes known `stageKey` values to app-side technical keys via `HelperWorkflowLocalizationKeys.presentation(for:)`, so legacy/raw helper text does not leak into UI when stage is known.
5. `CreatorHelperLogic` performs additional alias canonicalization for runtime compatibility (`ditto`/`catalina_ditto` → `catalina_copy`, `catalina_finalize` → `catalina_cleanup`, `asr_imagescan` → `imagescan`, `asr_restore` → `restore`) before setting UI state.
6. `CreationProgressView` renders title/status with `Text(LocalizedStringKey(...))`; resolved value comes from `Localizable.xcstrings` in currently selected app language.
7. `logLine` is never rendered in stage UI; it is logged to `HelperLiveLog` for diagnostics/export.
- Non-helper but related runtime labels (for example speed text) use `String(localized:)` keys, not hardcoded literals.
- Maintenance contract when adding or changing helper stage phrases:
1. Add/adjust key constants and `presentation(for:)` mapping in `HelperWorkflowLocalizationKeys`.
2. Keep `HelperWorkflowLocalizationExtractionAnchors.anchoredValues` synchronized with all runtime helper keys.
3. Update helper stage definitions in `macUSBHelper/main.swift` to use those keys.
4. Add translations in `Localizable.xcstrings` for all supported languages (`pl`, `en`, `de`, `ja`, `fr`, `es`, `pt-BR`, `zh-Hans`, `ru`) for both title and status keys.
5. Build and verify runtime in at least EN + PL to ensure no raw key or source-language fallback appears.

### 11.10 Logging and observability for helper path
- `HelperService` category:
- registration/status/repair lifecycle diagnostics.
- `HelperLiveLog` category:
- streamed helper stdout/stderr (`logLine`) from command execution and decode failures (including Catalina transition to `ditto`).
- format-target diagnostics (`requested`, `fallbackWhole`, `resolvedWhole`, `targetVolumePath`) emitted before formatting stages.
- app-side transfer monitor fallback diagnostics/recovery events and speed-based copied-data estimation when speed samples are temporarily unavailable.
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
- Preserve helper event fields (`stageTitleKey`, `statusKey`, `percent`, `logLine`) and technical-key localization contract.
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
- `macUSB/Features/Installation/UniversalInstallationView.swift` — Installer creation summary/start screen, destructive start-confirmation trigger (`Rozpocznij`), immediate navigation to `CreationProgressView`, and pre-start back action (`Wróć`) that preserves selected source/USB context.
- `macUSB/Features/Installation/CreationProgressView.swift` — Runtime helper progress UI (staged list, active-stage description + linear progress bar, stage-scoped write-speed label, cancel-in-progress action), and handoff to `FinishUSBView`.
- `macUSB/Features/Installation/CreatorLogic.swift` — Shared installation utilities used by the helper path (start/cancel alerts, cleanup, monitoring, flow reset/back helpers).
- `macUSB/Features/Installation/CreatorHelperLogic.swift` — Primary installation path via privileged helper (SMAppService + XPC), helper progress mapping, and helper cancellation flow.
- `macUSB/Features/Finish/FinishUSBView.swift` — Final screen, fallback cleanup safety net (race-safe when TEMP was already removed), supports success/failure/cancelled result mode (`Przerwano`), shows detected system icon in success summary row left slot (fallback to `externaldrive.fill`), total process duration summary (`Ukończono w MMm SSs` for success), duration logging, background-result system notification (disabled for cancelled mode), and optional cleanup overrides used by debug simulation.
- `macUSB/Shared/Models/Models.swift` — `USBDrive` (including `needsFormatting`), `USBPortSpeed`, `PartitionScheme`, `FileSystemFormat`, and `SidebarItem` definitions.
- `macUSB/Shared/Models/Item.swift` — SwiftData model stub (currently unused).
- `macUSB/Shared/UI/DesignTokens.swift` — Shared visual token definitions (window size, spacing, icon column, corner-radius hierarchy).
- `macUSB/Shared/UI/LiquidGlassCompatibility.swift` — Cross-version UI compatibility layer (`VisualSystemMode`, glass/fallback panel surfaces, primary/secondary button style wrappers).
- `macUSB/Shared/UI/BottomActionBar.swift` — Shared bottom action/status container used with `safeAreaInset(edge: .bottom)`.
- `macUSB/Shared/UI/StatusCard.swift` — Shared semantic status/info card wrapper.
- `macUSB/Shared/Services/LanguageManager.swift` — Language selection and locale handling.
- `macUSB/Shared/Services/MenuState.swift` — Shared menu state (skip analysis, external drives, notifications state, DEBUG copied-data label).
- `macUSB/Shared/Services/NotificationPermissionManager.swift` — Central notification permission and app-level toggle manager (default-off at first run, menu action, system settings redirect).
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

- `macUSB/App/macUSBApp.swift` → uses `ContentView`, `MenuState`, `LanguageManager`, `UpdateChecker`, `NotificationPermissionManager`, `HelperServiceManager`; in `DEBUG` also publishes `macUSBDebugGoToBigSurSummary` and `macUSBDebugGoToTigerSummary`, opens `${TMPDIR}/macUSB_temp` in Finder, and renders live copied-data informational rows.
- `macUSB/App/ContentView.swift` → presents `WelcomeView`, injects `LanguageManager`, applies window/toolbar configuration, calls `AppLogging.logAppStartupOnce()`, and maps debug notifications to delayed (2s) `FinishUSBView` routes (Big Sur and Tiger/PPC).
- `macUSB/Features/Welcome/WelcomeView.swift` → navigates to `SystemAnalysisView`, checks `version.json`, bootstraps helper readiness via `HelperServiceManager`, then triggers startup notification-permission flow.
- `macUSB/Features/Analysis/SystemAnalysisView.swift` → owns `AnalysisLogic`, calls its analysis and USB methods, updates `MenuState`, snapshots selected drive (`selectedDriveForInstallationSnapshot`) on navigation, forwards that stable target plus `detectedSystemIcon` to installation flow, and renders CTA layer through `BottomActionBar`.
- `macUSB/Features/Analysis/AnalysisLogic.swift` → calls `USBDriveLogic`, uses `AppLogging`, mounts images via `hdiutil`; forwards USB metadata into selected-drive state.
- `macUSB/Features/Installation/UniversalInstallationView.swift` → renders detected system icon in system info panel (with `applelogo` fallback), requires destructive confirmation before start, then starts helper path via `startCreationProcessEntry()` and routes to `CreationProgressView`; uses shared `StatusCard` and `BottomActionBar`.
- `macUSB/Features/Installation/CreationProgressView.swift` → renders helper runtime progress (pending/active/completed stage cards, status text, stage-scoped write-speed label), exposes cancel alert flow, navigates to `FinishUSBView`, and uses shared surfaces/buttons from UI compatibility layer.
- `macUSB/Features/Installation/CreatorHelperLogic.swift` → builds typed helper requests, coordinates helper execution/cancellation, and maps XPC progress events into UI state.
- `macUSB/Features/Installation/CreatorLogic.swift` → provides shared helper-path utilities (start/cancel alert flow, USB availability monitoring, emergency unmount, cleanup, immediate reset/back flow).
- `macUSB/Features/Finish/FinishUSBView.swift` → fallback cleanup safety net (unmount + conditional temp delete), result sound (prefers bundled `burn_complete.aif`), process duration summary/logging, optional background system notification gated by permission/toggle, reset callback, dedicated cancelled-mode UX, and shared bottom action/status layer.
- `macUSB/Shared/UI/DesignTokens.swift` → consumed by all primary flow views and window setup for consistent spacing/radii/window size.
- `macUSB/Shared/UI/LiquidGlassCompatibility.swift` → consumed by views for availability-safe panel and button styling (`macOS 26` glass vs `macOS 14/15` fallback).
- `macUSB/Shared/UI/BottomActionBar.swift` → consumed by `SystemAnalysisView`, `UniversalInstallationView`, `CreationProgressView`, and `FinishUSBView`.
- `macUSB/Shared/UI/StatusCard.swift` → consumed by feature screens for semantic cards.
- `macUSB/Shared/Services/LanguageManager.swift` → controls app locale, used by `ContentView` and menu.
- `macUSB/Shared/Services/MenuState.swift` → read/written by `macUSBApp.swift`, `SystemAnalysisView`, and `NotificationPermissionManager`.
- `macUSB/Shared/Services/NotificationPermissionManager.swift` → reads `UNUserNotificationCenter` state, updates `MenuState`, controls startup/menu alerts for notification permission, and opens system settings when blocked.
- `macUSB/Shared/Services/Helper/HelperServiceManager.swift` → registers/repairs/removes LaunchDaemon helper via `SMAppService`, reports readiness, presents startup Background Items approval prompt when needed, and shows helper status alerts (healthy short-form + full details dialog).
- `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift` → app-side XPC client that starts/cancels helper workflows and logs `logLine` events to `HelperLiveLog`.
- `macUSB/Shared/Services/Helper/HelperIPC.swift` → helper IPC payload contracts (request, progress event, result).
- `macUSB/Shared/Localization/HelperWorkflowLocalizationKeys.swift` → single source of truth for helper localization key IDs and extraction anchors used by String Catalog.
- `macUSBHelper/main.swift` → helper-side XPC service, root workflow executor, progress event emitter, and cancellation handling.
- `macUSB/Shared/Services/UpdateChecker.swift` → called from app menu.

---

## 14. Contributor Rules and Patterns
1. Polish-first localization: author new UI strings in Polish, then translate.
2. Do not add hidden behavior in the UI: show warnings for destructive operations.
3. Respect flow flags: `AnalysisLogic` flags are the source of truth for installation paths.
4. Keep the window fixed: UI assumes a 550×750 fixed layout.
5. Keep UI compatibility wrappers as the only entry point for cross-version visual styling:
- `macUSBPanelSurface`, `macUSBDockedBarSurface`, `macUSBPrimaryButtonStyle`, `macUSBSecondaryButtonStyle`.
6. Use shared UI primitives in the main flow:
- status/info panels via `StatusCard`,
- bottom action/status areas via `BottomActionBar`.
7. Concentricity is mandatory: spacing/radii must come from `MacUSBDesignTokens` unless a documented exception exists.
8. UI refactors must not change USB creation/helper behavior:
- do not alter helper workflow semantics, XPC request/response contracts, or stage transition logic in UI-only iterations.
9. Privileged helper operations must be observable: keep stage/status/progress-state updates flowing to UI and keep `logLine` in diagnostics logs (`HelperLiveLog`) rather than screen panels.
10. Helper stage/status strings must stay localizable through `Localizable.xcstrings`; helper sends technical keys and the app renders them with `LocalizedStringKey`.
11. Adding a new helper stage requires: new technical key IDs, translations for all supported languages, EN verification, and a full project build check.
12. Use `AppLogging` for all important steps: keep logs helpful for diagnostics.
13. Privileged install flow must run through `SMAppService` + LaunchDaemon helper in all configurations (no terminal fallback).
14. Do not break the Tiger Multi-DVD override: menu option triggers a specific fallback flow.
15. Debug menu contract: top-level `DEBUG` menu is allowed only for `DEBUG` builds; it must not be available in `Release` builds.
16. Required UI verification matrix for UX changes:
- compile and smoke-test on macOS 14 (Sonoma), macOS 15 (Sequoia), and macOS 26 (Tahoe),
- verify full flow (`Welcome → Analysis → UniversalInstallation → CreationProgress → Finish`),
- verify empty/analyzing/unsupported/warning/in-progress/success/fail/cancelled states,
- verify primary-action dominance and no tint conflicts between semantic cards and neutral helper cards,
- verify keyboard navigation, focus ring visibility, and VoiceOver labels.

### 14.1 AI Agent Instructions
- IMPORTANT RULE FOR AI AGENTS: Reading this document is mandatory, but not sufficient on its own.
- Before proposing or implementing changes, AI agents must also analyze the current codebase to build accurate runtime and architecture context.
- AI agents must write git commit messages in English: a clear title/summary line plus a concise body describing key changes.
- Do not use escaped newline sequences like `\n` in commit message text; use normal multi-line commit formatting only.
- AI agents should commit changes comprehensively (include all modified project files) by default.
- Exceptions to comprehensive commits:
- user explicitly requests a narrower commit scope, or
- modified files appear to be build artifacts/temporary/unnecessary outputs (for example Xcode build products).
- In artifact/temporary-output cases, the agent must explicitly report those files before committing and ask the user what to do.
- If a requested change is not uniform and multiple valid implementation variants exist, the agent must explain the differences/tradeoffs and ask the user to choose the direction before finalizing.

---

## 15. Potential Redundancies and Delicate Areas
- Update checking is duplicated: `WelcomeView` and `UpdateChecker` both read `version.json`.
- Legacy detection and special cases are complex: changes in `AnalysisLogic` affect multiple installation paths.
- Localization: some Polish strings are hard-coded in `Text("...")`; ensure keys exist in `Localizable.xcstrings`.
- Cleanup logic still has multiple safety nets (helper final stage, cancel/window emergency paths, `FinishUSBView` fallback); preserve their non-destructive intent when refactoring.
- `FinishUSBView` has a dedicated cancelled mode (`Przerwano`) that intentionally suppresses finish sound/background notification; preserve this distinction from success/failure.

---

## 16. Notifications Chapter
This chapter defines notification permissions, UI toggles, and delivery rules.

Core components:
- `NotificationPermissionManager` is the source of truth for notification policy.
- `MenuState.notificationsEnabled` is the effective notifications state used by menu label/icon.
- `WelcomeView` runs update check, then helper startup bootstrap, then notification state refresh/default initialization flow.
- `FinishUSBView` sends completion notification only when policy allows.

State model:
- System permission state comes from `UNUserNotificationCenter.getNotificationSettings()`.
- App-level toggle is stored in `UserDefaults` key `NotificationsEnabledInAppV1`.
- Effective enabled state (menu label/icon): `systemAuthorized && appEnabledInApp`.
- First-run default: app-level toggle is initialized to `false` when missing.

System status interpretation (as implemented):
- Treated as authorized: `.authorized`, `.provisional`.
- Treated as blocked: `.denied`.
- Treated as undecided: `.notDetermined`.

Startup flow:
1. `WelcomeView.onAppear` runs `checkForUpdates(completion:)`.
2. After update flow completes (including alert close), app calls `HelperServiceManager.bootstrapIfNeededAtStartup(...)`.
3. After helper startup bootstrap completion, app calls `NotificationPermissionManager.handleStartupFlowIfNeeded()`.
4. This ordering ensures helper approval alert (`requiresApproval`) is handled first, while notifications stay non-intrusive.
5. Startup notification behavior:
- no custom notification-permission prompt is shown automatically on first launch,
- app toggle is initialized to disabled (`false`) if missing,
- menu state is refreshed to reflect `systemAuthorized && appEnabledInApp`.

Menu behavior (`Opcje` → `Powiadomienia`):
- Menu state source: `MenuState.notificationsEnabled`.
- Dynamic label and icon:
- enabled: label `Powiadomienia włączone`, icon `bell.and.waves.left.and.right`
- disabled: label `Powiadomienia wyłączone`, icon `bell.slash`
- On tap, behavior depends on system status:
- Authorized/provisional: toggle app-level flag only (on/off in app), no redirection to system settings.
- Not determined: show enable prompt:
- Title: `Czy chcesz włączyć powiadomienia?`
- Body: `Pozwoli to na otrzymanie informacji o zakończeniu procesu przygotowania nośnika instalacyjnego.`
- Buttons: primary `Włącz powiadomienia`, secondary `Nie teraz`
- This prompt appears only after intentional user action from menu.
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
- No startup notification prompt is shown.
- Notification permission request is user-initiated from menu when status is `.notDetermined`.
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
- Menu actions and informational rows (localized labels):
- `Przejdź do podsumowania (Big Sur) (2s delay)`
- `Przejdź do podsumowania (Tiger) (2s delay)`
- `Otwórz macUSB_temp`
- Divider
- `Informacje`
- `Przekopiowane dane: xx.xGB` (read-only informational row)

Action behavior:
- Summary actions are immediate triggers that publish NotificationCenter events from `macUSBApp.swift`.
- Big Sur action publishes `macUSBDebugGoToBigSurSummary`.
- Tiger action publishes `macUSBDebugGoToTigerSummary`.
- `Otwórz macUSB_temp` opens `${TMPDIR}/macUSB_temp` in Finder when the folder exists.
- If `${TMPDIR}/macUSB_temp` does not exist, app presents warning `NSAlert` with title `Wybrany folder nie istnieje`.
- Copied-data informational row is backed by `MenuState.debugCopiedDataLabel` and refreshed every 2 seconds while helper workflow runs.

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
- Existing production flow remains `WelcomeView` → `SystemAnalysisView` → `UniversalInstallationView` → `CreationProgressView` → `FinishUSBView`.

Rules:
- Do not expose debug actions to end users in `Release`.
- Keep debug navigation deterministic and side-effect-safe.

---

End of document.
