# Localization Contract

## Source Policy

- Source language is Polish (`pl`) in `macUSB/Resources/Localizable.xcstrings`.
- New UI copy must be authored in Polish first.

## Runtime Policy

- All user-facing UI text must originate from localization catalog keys rather than prelocalized literal strings.
- UI state, workflow payloads, and helper transport must carry localization keys for as long as possible.
- APIs that accept localization keys should receive keys directly.
- Resolve a key with `String(localized:)` only at the presentation boundary when an API requires a `String`.
- Helper localization keys and app-side rendering keys must stay synchronized.
- In helper workflow transport/rendering, `titleKey` and `statusKey` fields must always carry localization catalog keys, never prelocalized literal text.

## Language Set Consistency

Supported language handling must remain coherent between runtime behavior and localization catalog.

## String Catalog Serialization Policy

`macUSB/Resources/Localizable.xcstrings` must be edited in the target serialization format produced by Xcode. Translation work must not introduce a compact or partially sorted JSON style that Xcode will rewrite later.

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

Update when localization source policy, key strategy, catalog serialization, extraction-state handling, or language coverage behavior changes.
