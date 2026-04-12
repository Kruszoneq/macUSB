# Non-Negotiable Behavior Contracts (Do Not Break)

## A) Sticky navbar with frosted transition

- `nav` is fixed.
- Toggle `body.scrolled` when `window.scrollY > 30`.
- Scrolled state applies frosted background, blur, and subtle divider.

## B) Shared navbar/footer injection

- Primary content pages must mount `#navbar` and `#footer` and load shared partials via `main.js`.
- Do not duplicate navbar/footer markup into each page.
- Exception: `/pages/about.html` remains a minimal legacy redirect.

## C) Base path compatibility

- Must work for both local mode (`''`) and GitHub Pages mode (`/macUSB`).
- Keep and replace `{{BASE}}` placeholders in partials via JS.

## D) Fixed theme contract

- No theme toggle in navbar.
- No `prefers-color-scheme` switching.
- No localStorage theme state.

## E) Guides dropdown behavior

- Works on desktop hover and touch/mobile click.
- Keyboard support required: Enter, Space, ArrowDown, Escape.

## F) Latest release fetch

- Fetch endpoint: `https://api.github.com/repos/Kruszoneq/macUSB/releases/latest`.
- Render `#latest-version` as `Latest version: <tag>`.
- On desktop, update release CTAs (`a.cta-button` targeting releases) to latest `.dmg` URL when available.
- On mobile/tablet, keep CTAs pointing to releases page.
- Fallback: if fetch fails, keep default release links.

## G) Homepage hero behavior

- Keep screenshot carousel.
- No background image layer mounted in hero.
- Scroll cue jumps to `#screenshots`.
- Keep screenshots uncropped:
  - container ratio `55 / 79`
  - image `object-fit: contain`

## H) Footer behavior

- Footer remains shared and includes static `support-button` Buy Me a Coffee link.
- Do not depend on Buy Me a Coffee widget script or JS fallback logic.

## I) PPC guide content lock

- Do not change Open Firmware command content in `/pages/guides/ppc_boot_instructions.html`.
- Styling changes are allowed through shared CSS.

## J) TOC policy

- Keep left sticky TOC only where content is long enough (Tiger guide).
- PPC guide remains without left TOC unless explicitly requested.

## K) About legacy redirect contract

- `/pages/about.html` remains lightweight legacy redirect.
- Redirect target: `/pages/create-bootable-macos-usb-on-apple-silicon.html`.
- Keep canonical on `about.html` pointing to merged page.
