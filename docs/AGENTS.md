# macUSB Website - Agent & Human Guide (Single Source of Truth)

This document defines the current architecture, design system, behavior contracts, and editing rules for the macUSB website.
Use it as the primary reference for both AI agents and human contributors.

## Table of Contents

- [0) How to use this document](#0-how-to-use-this-document)
- [1) Project overview](#1-project-overview)
- [2) Current file structure](#2-current-file-structure)
- [3) Design system (2026 refresh)](#3-design-system-2026-refresh)
- [4) Non-negotiable behavior contracts (Do NOT break)](#4-non-negotiable-behavior-contracts-do-not-break)
- [5) Navbar information architecture](#5-navbar-information-architecture)
- [6) Page-level content rules](#6-page-level-content-rules)
- [7) Responsive and accessibility requirements](#7-responsive-and-accessibility-requirements)
- [8) Implementation notes and gotchas](#8-implementation-notes-and-gotchas)
- [9) Development workflow](#9-development-workflow)
- [10) Acceptance checklist (required before shipping)](#10-acceptance-checklist-required-before-shipping)

---

## 0) How to use this document

- Treat this file as the single source of truth for site behavior and structure.
- If UI/UX conventions change, update this file in the same change set.
- Keep this document in English.

---

## 1) Project overview

**Project:** macUSB website (GitHub Pages static site)  
**Goal:** modern Apple-like product website with strong SEO, clear guides, and stable behavior across desktop/mobile.

Primary objectives:
- Showcase macUSB v2.0 value proposition.
- Support long-tail SEO for bootable macOS USB workflows.
- Preserve robust guide pages for Tiger Multi-DVD and PowerPC USB boot.
- Keep implementation framework-free (pure HTML/CSS/JS).

---

## 2) Current file structure

### Core website files
- `/index.html` - homepage (hero, product value, workflow, compatibility)
- `/assets/css/style.css` - full visual system and responsive behavior
- `/assets/js/main.js` - runtime behavior (partials injection, nav state, dropdown, release fetch, carousel, reveal, lightbox, TOC)

### Shared partials
- `/pages/partials.html` - shared navbar (single source of truth)
- `/pages/footer.html` - shared footer (single source of truth)

### Main pages
- `/pages/create-bootable-macos-usb-on-apple-silicon.html` - merged Why/About product + SEO page
- `/pages/about.html` - legacy URL redirect page to the merged Why page

### Guides
- `/pages/guides/ppc_boot_instructions.html` - PowerPC Open Firmware boot guide
- `/pages/guides/multidvd_tiger.html` - Tiger Multi-DVD guide

### Primary assets
- `/assets/icon/macUSBicon-v2.png` - current icon for nav/favicon/branding
- `/assets/screenshots/app-v2/*` - v2 app screenshots used on homepage and SEO page
- `/assets/screenshots/multidvd_tiger/*` - Tiger Multi-DVD guide screenshots (canonical sequence):
  - `01-files.png`
  - `02-cd1.png`
  - `03-cd2.png`
  - `04-info.png`
  - `05-cd2ok.png`
  - `06-creation.png`
  - `07-finish.png`

---

## 3) Design system (2026 refresh)

### Visual direction
- Apple-like, modern, minimal, clean hierarchy.
- Glass effect should be most visible on navbar in scrolled state.
- Avoid heavy visual clutter and avoid over-animated UI.

### Colors and theming
- Single fixed default theme (no system detection, no manual theme switch).
- Base color scheme is dark-oriented and remains `#303030` family for surfaces.
- Accent stays Apple-blue family.
- Global body background uses a subtle blue-to-blue-gray gradient overlay on `--bg-color`.

### Typography and spacing
- System font stack.
- High-contrast headings with clear hierarchy.
- Max content width around `980px` for docs pages and up to ~`1040-1120px` for homepage sections.

### Buttons and actions
- Use `cta-button` only for primary download actions.
- Use `card-button` for internal guide links and secondary page actions.
- Use `support-button` for voluntary Buy Me a Coffee support actions (non-primary CTA).
- `card-button` visual contract:
  - pill shape (`border-radius: 999px`)
  - subtle surface background (`--surface-1`)
  - 1px border (`--border-color`)
  - hover lift (`translateY(-1px)`) with `--surface-2`
- `support-button` visual contract:
  - secondary frosted-glass style with subtle blur
  - icon + text inline layout
  - must stay visually subordinate to the primary download `cta-button`
- Group secondary actions inside `.section-actions`.
- In Tiger Multi-DVD, the cross-link button under the final screenshot uses `.section-actions.after-guide-image` to keep extra spacing below image shadows.

### Motion
- Use smooth, subtle motion (`Balanced modern`): reveal and gentle transforms.
- Must support `prefers-reduced-motion: reduce` (disable non-essential transitions and animations).

---

## 4) Non-negotiable behavior contracts (Do NOT break)

### A) Sticky navbar with frosted transition
- `nav` is fixed.
- `body.scrolled` is toggled when `window.scrollY > 30`.
- Scrolled state applies frosted background + blur + subtle divider.

### B) Shared navbar/footer injection
- All primary content pages use `<div id="navbar"></div>` and `<div id="footer"></div>`.
- `main.js` injects:
  - `${basePrefix}/pages/partials.html`
  - `${basePrefix}/pages/footer.html`
- Do not duplicate navbar/footer markup into each page.
- Exception: `/pages/about.html` is a minimal legacy redirect page and intentionally does not mount shared partials.

### C) Base path compatibility
- `main.js` must support both:
  - local dev: `''`
  - GitHub Pages: `/macUSB`
- In partials, keep `{{BASE}}` placeholders and replace via JS.

### D) Fixed theme contract
- Navbar does not include a theme toggle.
- No `prefers-color-scheme` switching.
- No localStorage theme state.

### E) Guides dropdown behavior
- Works on desktop hover and touch/mobile click.
- Keyboard support required: Enter/Space/ArrowDown, Escape.

### F) Latest release fetch
- Fetch from: `https://api.github.com/repos/Kruszoneq/macUSB/releases/latest`
- Render in `#latest-version` as `Latest version: <tag>`.
- Resolve primary download CTAs (`a.cta-button` pointing to GitHub releases) to the latest `.dmg` asset URL on desktop devices when API data is available.
- On mobile/tablet devices, keep download CTAs pointing to the GitHub releases page (no direct automatic `.dmg` link).
- Fallback behavior: if API fetch fails, keep default release page links.

### G) Hero behavior (homepage)
- Hero keeps screenshot carousel.
- Hero does not currently mount a background image layer.
- Scroll cue jumps to `#screenshots` section.
- Home hero screenshots must remain fully visible (no top/bottom cropping):
  - container ratio `55 / 79`
  - images with `object-fit: contain`

### H) Footer behavior
- Footer remains shared and includes a static `support-button` Buy Me a Coffee link matching the homepage support button style.
- Footer does not rely on the Buy Me a Coffee widget script or JS fallback logic.

### I) PPC guide content lock
- Do not change Open Firmware command content in `/pages/guides/ppc_boot_instructions.html`.
- Styling updates are allowed through shared CSS only.

### J) TOC policy
- Keep left sticky TOC only where content is long enough (Tiger guide).
- PPC guide remains without left TOC unless scope is explicitly changed.

### K) About legacy redirect contract
- `/pages/about.html` must remain a lightweight legacy redirect.
- Redirect target: `/pages/create-bootable-macos-usb-on-apple-silicon.html`.
- Keep canonical on `about.html` pointing to the merged page.

---

## 5) Navbar information architecture

Top-level navigation currently includes:
- `Why macUSB` (SEO page)
- `Guides` dropdown
- `GitHub`

Guides dropdown groups:
- **macUSB** -> Tiger Multi-DVD USB
- **PowerPC** -> PowerPC USB Boot

---

## 6) Page-level content rules

### Homepage (`/index.html`)
Must include:
- Product hero with icon, headline, subtitle, primary download CTA, and secondary `Support macUSB` CTA.
- Latest version and minimum requirement (macOS 14.6+).
- No hero badge.
- Value section (what app does and benefits).
- Workflow section (how it works).
- Compatibility + guide bridge links.
- Browser title format: `macUSB - <text>`.

### Legacy About URL (`/pages/about.html`)
- This page is a legacy redirect only.
- It must not contain competing long-form content.
- Required elements: canonical to merged page, redirect behavior, and fallback link.

### SEO page (`/pages/create-bootable-macos-usb-on-apple-silicon.html`)
- English-only merged product + SEO page (single source for Why/About content).
- Must semantically cover intents equivalent to:
  - "how to make a bootable macOS USB"
  - "create bootable macOS installer on Apple Silicon"
  - "bootable USB for older macOS versions"
  - "Tiger/Leopard bootable USB for PowerPC"
- Include metadata: title, description, canonical, OG, Twitter.
- Include structured data: `SoftwareApplication` and `FAQPage`.
- Include FAQ block and internal links to guides/releases.
- Copy rules: describe current app capabilities only; do not use changelog-style sections such as "What's new", "Added", "Changed", or "Improved".

### Guides
- Preserve procedural clarity and direct language.
- Keep screenshot zoom support.
- Keep Tiger guide TOC auto-generated + scrollspy behavior.
- Reciprocal cross-guide links must be rendered as `card-button` actions (not plain inline links/callout text):
  - Tiger guide -> PowerPC USB boot instructions button
  - PowerPC guide -> Tiger Multi-DVD creation button
- Tiger Multi-DVD guide flow must keep the current screenshot narrative:
  - Disc files prepared (Finder view)
  - CD1 auto-detection success
  - CD2+ detection issue state
  - skip-analysis warning modal
  - forced Tiger recognition state
  - operation details/start screen
  - completion screen with PowerPC instructions link

### Browser title convention (all pages)
- Homepage must use: `macUSB - <text>`.
- Every other page must use: `<text> - macUSB`.
- Do not use `|` or `—` in the `<title>` pattern.

---

## 7) Responsive and accessibility requirements

### Mobile-first quality gate
- Target smartphone widths: 360, 390, 414 px.
- No horizontal overflow.
- CTA and body text must remain readable.
- Dropdown/nav interactions must remain touch-friendly.
- On smartphone widths (`<=768px`), homepage hero icon is centered; on desktop it stays left-aligned.

### Accessibility
- Keyboard-focus styles required.
- `prefers-reduced-motion` must disable non-essential animation.
- Keep semantic heading order and descriptive alt text.

---

## 8) Implementation notes and gotchas

- Always include `main.js` and `style.css` with correct relative paths:
  - index: `assets/...`
  - pages: `../assets/...`
  - guides: `../../assets/...`
- `main.js` updates CSS vars:
  - `--vh`
  - `--nav-height`
  - `--page-header-offset`
- Avoid inline styles unless absolutely necessary.
- Do not replace partial injection with static copied nav/footer.

---

## 9) Development workflow

Local dev server example from repo root:
- `python3 -m http.server 8000 --bind 0.0.0.0`

When making changes, verify:
- local path mode and `/macUSB` base path mode
- nav/footer injection on all pages
- release fetch + guides dropdown
- guide image zoom and Tiger TOC behavior

### Commit message convention
- All commit messages must be written in English.
- Use a clear title plus a concise description focused on the most important changes.
- The description may be multi-line when needed.
- Do not use literal `\n` escape sequences in commit messages; use real multi-line commit bodies instead.
- Minor or non-essential details can be omitted from the commit description.

---

## 10) Acceptance checklist (required before shipping)

- [ ] Navbar renders on index/SEO/guides via partial injection.
- [ ] Footer renders on index/SEO/guides via partial injection.
- [ ] Sticky/frosted navbar behavior works and remains readable in the default fixed theme.
- [ ] No theme toggle is rendered in navbar.
- [ ] No system theme switching changes page appearance.
- [ ] Guides dropdown works on desktop hover, mobile click, and keyboard.
- [ ] Latest release fetch updates `#latest-version`.
- [ ] On desktop, download CTAs (`.cta-button`) resolve to the latest GitHub `.dmg` asset when API response includes it.
- [ ] On mobile/tablet, download CTAs keep linking to the GitHub releases page.
- [ ] Homepage hero includes both CTAs: primary `Download for macOS` and secondary `Support macUSB`.
- [ ] Homepage hero carousel works smoothly and screenshots are not cropped.
- [ ] `#screenshots` anchor and scroll cue behavior work.
- [ ] PPC guide command content remains unchanged.
- [ ] Cross-guide links in Tiger/PPC guides are rendered as `card-button` actions.
- [ ] Tiger guide TOC auto-generation and scrollspy remain stable.
- [ ] SEO page has complete metadata and internal links.
- [ ] SEO page includes `SoftwareApplication` and `FAQPage` structured data.
- [ ] `/pages/about.html` redirects to the merged SEO page and keeps canonical to that URL.
- [ ] Mobile layouts pass 360/390/414 width checks without overflow.
- [ ] `prefers-reduced-motion` fallback is respected.

---
