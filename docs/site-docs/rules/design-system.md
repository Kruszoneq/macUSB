# Design System (Cal-style Light Refresh)

## Visual direction

- Modern, restrained, white-first editorial SaaS style.
- Flat white navbar by default; frosted effect only in scrolled sticky state.
- Real product screenshots are the primary visual artifact.
- Keep interfaces clean and legible with clear hierarchy and generous whitespace.

## Colors and theming

- Single fixed default theme (no theme switch, no system theme detection).
- Primary canvas: `#ffffff`.
- Primary action color: `#111111` with active/pressed shade `#242424`.
- Card surface: light gray (`#f5f5f5`) with hairline borders.
- Footer closes pages on dark surface (`#101010`) with soft light text.
- Accent colors are minimal and non-dominant.

## Typography and spacing

- Display stack: `Manrope`, fallback `Inter`.
- Body/UI stack: `Inter`.
- Display headlines use weight `600` and tighter letter-spacing.
- Body copy remains neutral and highly readable.
- Docs content max width around `980px`.
- Homepage section widths up to around `1120-1200px`.
- Section rhythm targets large-band spacing (roughly 72-96px on desktop).

## Buttons and actions

- `cta-button`: primary download action only, dark fill with light text, medium radius.
- `card-button`: secondary actions and guide links, outlined/light style, pill shape.
- `support-button`: secondary support action; lower visual priority than `cta-button`.

`card-button` contract:
- pill shape (`border-radius: 999px`)
- subtle light surface background
- 1px hairline border
- hover lift (`translateY(-1px)`) with soft background shift

`support-button` contract:
- visually secondary to primary CTA
- icon + text inline layout
- in footer, allowed dark-elevated variant while preserving secondary hierarchy

- Group secondary actions inside `.section-actions`.
- In Tiger guide, cross-link below final screenshot uses `.section-actions.after-guide-image`.

## Motion

- Use subtle, smooth, balanced motion.
- Must support `prefers-reduced-motion: reduce` by disabling non-essential transitions/animations.
