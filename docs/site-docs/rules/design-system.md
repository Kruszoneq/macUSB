# Design System (2026 Refresh)

## Visual direction

- Apple-like, modern, minimal, clear hierarchy.
- Frosted/glass effect should be most visible on navbar in scrolled state.
- Avoid heavy visual clutter and over-animation.

## Colors and theming

- Single fixed default theme.
- No system theme detection or manual theme switch.
- Base surfaces remain in the `#303030` family.
- Accent remains Apple-blue family.
- Body background uses a subtle blue to blue-gray gradient overlay on `--bg-color`.

## Typography and spacing

- Use system font stack.
- Keep heading hierarchy high-contrast and clear.
- Docs content max width around `980px`.
- Homepage section widths up to around `1040-1120px`.

## Buttons and actions

- `cta-button`: primary download action only.
- `card-button`: internal guide links and secondary page actions.
- `support-button`: voluntary Buy Me a Coffee support action (must remain visually secondary to primary CTA).

`card-button` contract:
- pill shape (`border-radius: 999px`)
- subtle surface background (`--surface-1`)
- 1px border (`--border-color`)
- hover lift (`translateY(-1px)`) with `--surface-2`

`support-button` contract:
- frosted secondary style with subtle blur
- icon + text inline layout
- visual priority lower than primary `cta-button`

- Group secondary actions inside `.section-actions`.
- In Tiger guide, cross-link below final screenshot uses `.section-actions.after-guide-image` for spacing below image shadows.

## Motion

- Use subtle, smooth, balanced motion.
- Must support `prefers-reduced-motion: reduce` by disabling non-essential transitions/animations.
