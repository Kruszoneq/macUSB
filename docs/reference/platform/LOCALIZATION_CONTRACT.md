# Localization Contract

## Source Policy

- Source language is Polish (`pl`) in every string catalog under `macUSB/Resources/`.
- New localized UI copy must be authored in Polish first; DEBUG-only text follows the separate runtime contract below.

## Runtime Policy

- All user-facing UI text available outside DEBUG originates from localization catalog keys rather than prelocalized literal strings.
- DEBUG-only UI text is displayed as untranslated English literals from code and has no localization keys or catalog entries. This exception includes controls, statuses, summary values, and alert messages; these literals are excluded from automatic string extraction.
- Semantic localization identifiers follow `area.feature.element`, with additional segments where needed. Polish source text and translations are catalog values; code references the same key in its owning table.
- Localized UI state, workflow payloads, and helper transport must carry localization keys for as long as possible.
- APIs that accept localization keys should receive keys directly.
- Resolve a key with `String(localized:)` only at the presentation boundary when an API requires a `String`.
- Helper localization keys and app-side rendering keys must stay synchronized.
- In helper workflow transport/rendering, `titleKey` and `statusKey` fields must always carry localization catalog keys, never prelocalized literal text.

## Language Set Consistency

Supported language handling must remain coherent between runtime behavior and localization catalog.

## Catalog and Table Map

Each `.xcstrings` file represents a separate localization table in the app bundle. The table name is the filename without its extension; a key prefix does not choose a table.

The table map covers localized text; DEBUG-only English literals are outside catalog ownership.

| Catalog | Table | Scope |
| --- | --- | --- |
| `macUSB/Resources/App.xcstrings` | `App` | Welcome screen, system menu bar and its actions, update checks, language/restart UI, permission and notification prompts, diagnostic-log export, helper status/repair/readiness/trust UI, startup toasts, and the Tools-menu raw-image warning and picker. |
| `macUSB/Resources/Analysis.xcstrings` | `Analysis` | Source and USB selection, requirements, analysis progress/results, recognition and compatibility messages, capacity alerts, transitions, and the manual SHA-256 action, sheet, and errors across all supported workflows. |
| `macUSB/Resources/Summary.xcstrings` | `Summary` | Complete pre-start summary: selected source/target, process and duration cards, permissions, Linux/raw-image guidance, Windows boot-mode/WIM prerequisites/automatic configuration, Rosetta status/license UI, start/back actions, destructive confirmation, and Windows helper-capability preflight errors. |
| `macUSB/Resources/Downloader.xcstrings` | `Downloader` | Downloader discovery, selection, download, verification, installer assembly, disk-image output, cleanup, summary, alerts, and completion notifications. Shared labels used by downloader have downloader-owned copies; its system-menu entry belongs to `App`. |
| `macUSB/Resources/Creator.xcstrings` | `Creator` | USB execution, cancellation, unmount recovery, progress, and helper workflow titles/statuses for macOS, Windows, Linux, and manual raw images. Shared execution labels have creator-owned copies. Summary copies of labels also used during execution stay in `Summary`. |
| `macUSB/Resources/FinishUSB.xcstrings` | `FinishUSB` | Finish result, Linux/raw-image final error cards, cleanup, duration, next-step guidance, safe/forced ejection, and USB completion notifications. Shared finish labels have finish-owned copies. |
| `macUSB/Resources/Localizable.xcstrings` | `Localizable` (default) | Residual shared and legacy entries for areas without a dedicated catalog. Active app/menu/helper UI, analysis, and pre-start summary text use their named tables. |

Named-table lookups use `String(localized: ..., table: "App")`, `Text(..., tableName: "Analysis")`, or a `LocalizedStringResource` that carries the owning table. Summary, Creator, Downloader, and FinishUSB use the same APIs with their respective table names. Dynamic-key rendering and extraction anchors use the same owning table; intentionally indirect keys are manually managed. Resource-valued divider titles, macOS architecture messages, and Windows BIOS/UEFI card titles/descriptions carry their table through intermediate APIs so Xcode does not extract them into `Localizable`.

## Workflow and Shared Key Names

Keys specific to a workflow must contain its name. Follow the established Creator/Finish naming scheme: the stage or area comes first, followed by `macos`, `windows`, `linux`, or `raw_image`, then the feature and element. More precise macOS families such as `ppc`, `catalina`, `sierra`, `mavericks`, or `tiger` can follow `macos`.

Examples:

- `app.macos.tiger.override.message`
- `analysis.macos.architecture.intel_incompatible.title`
- `analysis.windows.server.unsupported_edition.description`
- `analysis.linux.unknown.display_name`
- `summary.windows.autounattend.card.title`
- `summary.macos.ppc.process.restore`
- `summary.raw_image.unreadable.description`
- `creator.windows.workflow.prepare_target.status`

Text common to several workflows uses universal stage/element keys, such as `analysis.action.proceed`, `analysis.usb.requirements.capacity`, `summary.action.start`, `summary.process.unmount`, or `creator.workflow.cleanup_temp.status`. Do not assign a shared stage label to a single workflow merely because it first appeared there. Existing Windows finish guidance retains its established `finish.nextsteps.windows.pc.*` identifiers.

The identifier prefix and table ownership are separate: every consumer must select the table explicitly, including dynamic lookup and extraction sites.

Helper workflow localization constants are shared between app and daemon and now emit `creator.*` identifiers. The IPC schema, workflow kinds, and technical stage identifiers remain unchanged. App-side decoding maps earlier `helper.workflow.*` title/status identifiers through `HelperWorkflowLocalizationKeys.catalogKey(for:)`, including individual macUSBoot phase statuses, before rendering them from `Creator`.

Removing an entry from `Localizable` is safe only after its remaining consumers have been checked; copied shared entries stay available to their original consumers. Migrated Polish source-text keys retain their exact effective Polish value explicitly under `pl` in the destination catalog. The App, Analysis, Summary, Creator, and FinishUSB migrations retain existing wording in all 13 supported languages and mark intentionally indirect entries as manually managed. App, Analysis, and Summary contain explicit Polish values even where the previous source-text identifier supplied the Polish fallback. Branding slogans, detected product names, filenames, architecture labels, BIOS/UEFI abbreviations, and command examples remain existing verbatim data; no new translations are authored for them.

## String Catalog Serialization Policy

Every `.xcstrings` catalog under `macUSB/Resources/` uses the target serialization format produced by Xcode. Translation work must not introduce a compact or partially sorted JSON style that Xcode will rewrite later.

Required format:

- use two spaces for every indentation level;
- use Xcode's spaced separator form, for example `"de" : {` and `"state" : "translated"`;
- keep every object member and every `stringUnit` field on its own line; never use compact inline localization objects such as `"de":{"stringUnit":...}`;
- keep entries in the `strings` dictionary in Xcode's deterministic, case-insensitive natural catalog order instead of prepending or appending a block outside its sorted position; symbols are ordered before text, and semantic keys are collated with the surrounding source strings;
- keep locale identifiers inside `localizations` in lexicographic order, for example `de`, `en`, `es`, `fr`, `it`, `ja`, `nl`, `pl`, `pt-BR`, `ru`, `tr`, `uk`, `vi`, `zh-Hans` for the complete supported set;
- preserve Xcode's schema property order and top-level order: `sourceLanguage`, `strings`, then `version`;
- do not substitute code-point sorting or run a general-purpose JSON formatter whose output differs from Xcode serialization.

If a live key is intentionally resolved through dynamic presentation indirection and therefore cannot be found by automatic string extraction, mark it with `"extractionState" : "manual"` in the same Xcode serialization style. Do not leave an actively used key marked as `stale` merely because extraction cannot see the dynamic reference.

Before finishing translation work, verify that opening or saving the catalog in Xcode does not produce a formatting-only diff and separately review any extraction-state changes as semantic metadata changes.

## Update Trigger

Update when catalog ownership, table selection, localization source policy, key strategy, catalog serialization, extraction-state handling, or language coverage behavior changes.
