# Design System Contract

This file is the source of truth for UI language consistency across current and future features.

## Styling Direction

The app uses an Apple-like, liquid-glass-compatible style with shared surfaces, spacing tokens, and action zones.

Core contract:
- consistent panel/docked surface semantics,
- consistent hierarchy of status cards,
- consistent CTA behavior and bottom action bars,
- consistent inactive/active visual behavior across windows and states.

## Required UI Primitives

Use wrappers from `LiquidGlassCompatibility.swift`:
- `macUSBPanelSurface`
- `macUSBDockedBarSurface`
- `macUSBPrimaryButtonStyle`
- `macUSBSecondaryButtonStyle`

Use spacing/radius tokens from `MacUSBDesignTokens`.
Use `BottomActionBar` with `safeAreaInset(edge: .bottom)` for bottom action zones.

## Window/Layout Contract

- Main flow window assumptions: `550 x 750`.
- Downloader and helper UI should remain visually coherent with the same design language.
- DEBUG-only UI must never appear in Release builds.

## Copy and Tone

- User-facing copy should remain concise, calm, and Apple-like.
- Polish is authored first in localization source.
- Error messaging should be actionable for users, with deep technical detail in logs.

## Future Feature Rule

Every new feature must follow this design language by default.
Any intentional design deviation should be documented before implementation.

## Update Trigger

Update when primitives, token policy, or core interaction language changes.
