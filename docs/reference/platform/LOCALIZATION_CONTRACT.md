# Localization Contract

## Source Policy

- Source language is Polish (`pl`) in `macUSB/Resources/Localizable.xcstrings`.
- New UI copy must be authored in Polish first.

## Runtime Policy

- Static UI text should map cleanly through localization catalog.
- Runtime non-`Text` user-facing strings should use `String(localized:)`.
- Helper localization keys and app-side rendering keys must stay synchronized.
- In helper workflow transport/rendering, `titleKey` and `statusKey` fields must always carry localization catalog keys, never prelocalized literal text.

## Language Set Consistency

Supported language handling must remain coherent between runtime behavior and localization catalog.

## Update Trigger

Update when localization source policy, key strategy, or language coverage behavior changes.
