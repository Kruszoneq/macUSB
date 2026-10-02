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
| `macUSB/Resources/Downloader.xcstrings` | `Downloader` | Downloader discovery, selection, download, verification, installer assembly, disk-image output, cleanup, summary, alerts, and completion notifications. Shared labels used by downloader have downloader-owned copies. |
| `macUSB/Resources/Localizable.xcstrings` | `Localizable` (default) | App-wide text and areas without a dedicated catalog, including analysis, USB creation, finish, menus, and helper workflow keys. |

Named-table lookups use `String(localized: ..., table: "Downloader")`, `Text(..., tableName: "Downloader")`, or a `LocalizedStringResource` that carries the table. Dynamic-key rendering uses the same owning table. Automatic extraction must see the intended table at literal lookup sites; intentionally indirect keys are manually managed.

Catalog separation does not require changing helper IPC payloads or workflow identifiers. The app chooses the presentation table for keys received from the helper. Removing an entry from `Localizable` is safe only after its remaining consumers have been checked; copied shared entries stay available to their original consumers.

## String Catalog Serialization Policy

Every `.xcstrings` catalog under `macUSB/Resources/` uses the target serialization format produced by Xcode. Translation work must not introduce a compact or partially sorted JSON style that Xcode will rewrite later.

Required format:

- use two spaces for every indentation level;
- use Xcode's spaced separator form, for example `"de" : {` and `"state" : "translated"`;
- keep every object member and every `stringUnit` field on its own line; never use compact inline localization objects such as `"de":{"stringUnit":...}`;
- keep entries in the `strings` dictionary in Xcode's deterministic, case-insensitive natural catalog order instead of prepending or appending a block outside its sorted position; symbols are ordered before text, and semantic keys are collated with the surrounding source strings;
- keep locale identifiers inside `localizations` in lexicographic order, for example `de`, `en`, `es`, `fr`, `it`, `ja`, `pl`, `pt-BR`, `ru`, `tr`, `uk`, `vi`, `zh-Hans` for the complete supported set;
- preserve Xcode's schema property order and top-level order: `sourceLanguage`, `strings`, then `version`;
- do not substitute code-point sorting or run a general-purpose JSON formatter whose output differs from Xcode serialization.

If a live key is intentionally resolved through dynamic presentation indirection and therefore cannot be found by automatic string extraction, mark it with `"extractionState" : "manual"` in the same Xcode serialization style. Do not leave an actively used key marked as `stale` merely because extraction cannot see the dynamic reference.

Before finishing translation work, verify that opening or saving the catalog in Xcode does not produce a formatting-only diff and separately review any extraction-state changes as semantic metadata changes.

## Update Trigger

Update when catalog ownership, table selection, localization source policy, key strategy, catalog serialization, extraction-state handling, or language coverage behavior changes.
