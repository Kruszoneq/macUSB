# Design System Contract

This file is the source of truth for UI language consistency across current and future features.

## Styling Direction

The app uses an Apple-like, liquid-glass-compatible style with shared surfaces, spacing tokens, and action zones.

Core contract:
- consistent panel/docked surface semantics,
- consistent hierarchy of status cards,
- consistent CTA behavior and bottom action bars,
- neutral in-app toast surfaces for transient status changes,
- consistent inactive/active visual behavior across windows and states.

## Required UI Primitives

Use wrappers from `LiquidGlassCompatibility.swift`:
- `macUSBPanelSurface`
- `macUSBDockedBarSurface`
- `macUSBPrimaryButtonStyle`
- `macUSBSecondaryButtonStyle`

Use spacing/radius tokens from `MacUSBDesignTokens`.
Use `BottomActionBar` with `safeAreaInset(edge: .bottom)` for bottom action zones.
Use global in-app toasts only for transient, non-blocking state changes; they should use a neutral native SwiftUI glass surface on systems that support Liquid Glass and a neutral fallback surface on older macOS versions.

## Window/Layout Contract

- Main flow window assumptions: `550 x 750`.
- Main flow startup position must not be force-centered; window placement should follow system/default restoration behavior.
- Downloader and helper UI should remain visually coherent with the same design language.
- DEBUG-only UI must never appear in Release builds.

## Motion and Dynamic Content Contract

Visibility changes initiated by the user must be animated consistently when they affect expandable or filtered lists, contextual banners/status cards, or conditional actions. Appearance and disappearance are equally important: never animate only one direction.

### Expandable lists and contextual banners

- Apply the visibility state change inside `withAnimation(.easeInOut(duration: 0.24))`.
- Use the same animation transaction for the affected list rows and any banner or `StatusCard` whose visibility follows that list, selection, or filter state. They must not appear or disappear in separate, visually disconnected steps.
- Keep row identity stable so SwiftUI animates insertion, removal, and layout movement instead of replacing the whole list.
- For a vertically inserted or removed banner, expandable section, or list-adjacent status block, prefer a symmetric `.move(edge: .top).combined(with: .opacity)` transition. A filtered list can rely on the shared animated layout update when its rows already have stable identity.
- Changing presentation options must update the current in-memory results. Do not rerun discovery, clear unrelated state, or introduce artificial delays solely to produce an animation.

The downloader options for Public Beta visibility and showing all available versions are the reference implementation for animated filter changes.

### Conditional buttons and header actions

- A button that is conditionally inserted into or removed from a header or action group uses a symmetric `.scale(scale: 0.85).combined(with: .opacity)` transition.
- Animate the containing layout with `.easeInOut(duration: 0.22)` and key it to the Boolean visibility condition, so neighboring controls move smoothly while the button appears or disappears.
- Remove a hidden action from the view hierarchy instead of leaving an invisible interactive control. Use opacity only for a deliberate disabled-state treatment, not as a substitute for conditional visibility.
- Preserve the existing shared button style, tint, disabled behavior, help text, and accessibility semantics throughout the transition.

The downloader prerequisite warning action is the reference implementation for conditional button visibility.

### Sequential process stages

- When a running process advances, the completed stage and the newly active stage must update in one shared `easeInOut` animation lasting `0.24` seconds.
- Keep stage-row identity stable and key the animation to the complete set of visual stage states, so progress and speed updates do not retrigger the list transition.
- Replace the visual contents of a stage card with a symmetric opacity plus subtle `0.98` scale transition. The containing stage list must animate the corresponding height changes so the active card collapses as the next card expands.
- Animation remains presentation-only. Do not delay, reorder, or merge workflow events to accommodate it.

The downloader and USB creation process screens share this stage-transition behavior.

## Copy and Tone

- User-facing copy should remain concise, calm, and Apple-like.
- Polish is authored first in localization source.
- Error messaging should be actionable for users, with deep technical detail in logs.

## Future Feature Rule

Every new feature must follow this design language by default.
Any intentional design deviation should be documented before implementation.

## Update Trigger

Update when primitives, token policy, motion behavior, or core interaction language changes.
