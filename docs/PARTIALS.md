# Navbar and Footer Partials

## Purpose

This document is the source-of-truth reference for shared navbar/footer content and integration rules.
Runtime markup lives in:

- `pages/partials.html` (navbar)
- `pages/footer.html` (footer)

## Integration Contract

Primary content pages must include:

- `<div id="navbar"></div>`
- `<div id="footer"></div>`

and load shared injection runtime:

- `assets/js/core/partials-nav-footer.js`

The script injects:

- `${basePrefix}/pages/partials.html`
- `${basePrefix}/pages/footer.html`

## Base Path Rules

- Keep `{{BASE}}` placeholders in partial markup where project-local links/assets are used.
- `partials-nav-footer.js` replaces `{{BASE}}` at runtime for:
  - local mode (`''`)
  - GitHub Pages mode (`/macUSB`)

## Current Navbar Content (must exist)

- Brand link to homepage (`{{BASE}}/index.html`)
  - icon: `{{BASE}}/assets/icon/macUSBicon-v2.png`
  - label: `macUSB`
- Right-side GitHub link:
  - `https://github.com/Kruszoneq/macUSB`
- Theme toggle button:
  - role `switch`
  - dynamic `aria-checked`
  - label/title updated by theme runtime

## Current Footer Content (must exist)

- Primary footer CTA link:
  - label `Download for macOS`
  - target `https://github.com/Kruszoneq/macUSB/releases`
- Support link:
  - label `Support macUSB`
  - target `https://www.buymeacoffee.com/kruszoneq`
- Latest release placeholder element:
  - `data-latest-version`
  - default text `Latest release`
- Copyright line:
  - `Copyright © 2025-2026 Kruszoneq`

## Editing Constraints

- Do not copy/paste navbar/footer into each page; keep partial injection architecture.
- Keep accessibility attributes intact for interactive elements.
- Keep icon + label structure for CTA and support links.
- When navbar/footer content changes, update this document in the same change set.
