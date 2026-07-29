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

## Update Trigger

Update when localization source policy, key strategy, or language coverage behavior changes.
