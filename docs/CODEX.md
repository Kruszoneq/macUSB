# macUSB Website — AI Codex Context & Rules (Single Source of Truth)

This document defines the working rules, design language, site structure, and non-negotiable behaviors of the macUSB website (GitHub Pages).  
Purpose: allow an AI assistant (Codex) to continue development consistently, without breaking existing UX, animations, or functionality.

---

## 0) How to use this document (meta rules)

- Treat this file as the single source of truth whenever it is referenced by the user.
- When new UI/UX patterns or behaviors are introduced, update this file in the same change.
- Always add a short entry to the Changelog when you append or change rules here.

---

## 1) Project Overview

**Project:** macUSB (open-source macOS app for creating bootable installers)  
**Website:** lightweight static site hosted on GitHub Pages  
**Repo:** Kruszoneq/macUSB  
**Branch for site:** `gh-pages` (or equivalent structure for Pages)

**Primary goals:**
- Apple-like landing page (clean, minimal, high polish).
- Clear docs/guides pages in Apple Docs style.
- Zero frameworks; pure HTML/CSS/JS.
- Preserve performance and simplicity.
- SEO-friendly, long-tail query oriented guides.

---

## 2) Folder / File Structure (Current)

Key web files:
- `/index.html` — landing
- `/assets/css/style.css` — all styling
- `/assets/js/main.js` — behavior + navbar injection + theme + dropdown + screenshots + GitHub release fetch + lightbox + TOC generator/scrollspy
- `/pages/partials.html` — shared NAVBAR partial (single source of truth for nav)
- `/pages/about.html` — About page
- `/pages/guides/ppc_boot_instructions.html` — PowerPC boot guide
- `/pages/guides/multidvd_tiger.html` — Tiger Multi-DVD guide

Assets:
- `/assets/icon/macUSBiconPNG.png` — favicon + icons
- `/assets/screenshots/app/*` — app screenshots used in landing carousel
- `/assets/screenshots/multidvd_tiger/*` — guide screenshots

IMPORTANT: All pages must load the navbar from `/pages/partials.html` via JS injection (see Section 4).

---

## 3) Design System / Style (Apple-like)

### Typography & layout
- Use system fonts: `-apple-system`, `BlinkMacSystemFont`, etc.
- Large, confident headings; airy spacing.
- Content max width: ~980px for pages.
- Rounded corners; subtle borders; frosted nav on scroll.

### Landing layout (index)
- Hero is full-viewport and split on desktop: left media slider, right content (logo/title/subtitle/CTA/version/requirements).
- On narrower screens, hero stacks content above media and recenters text.
- Slider should visually match the height of the hero content block (icon/title/text/CTA).
- The `#screenshots` section contains the three feature cards, then the section title, then three stacked rows of screenshots with descriptions.

### Colors & theming
- Theme supports: system auto + manual override.
- Dark theme background is not pure black; intentionally uses `#303030`.
- Light theme background remains Apple-ish; do not over-darken “surfaces”.
- Keep accents Apple-blue (`--accent-color`) with appropriate dark variant.

### Motion
- Smooth transitions using cubic-bezier (Apple-ish).
- Respect `prefers-reduced-motion: reduce` (disable transitions & smooth scrolling).
- No janky/abrupt state changes.

---

## 4) Non-negotiable Behaviors (Do NOT break)

### A) Sticky Navbar animation on scroll
- `nav` is fixed.
- When `window.scrollY > 30`, `body.scrolled` is added.
- Scrolled state uses frosted background + blur and shows small icon in nav.
- Avoid layout jumps; keep transitions smooth.

### B) Navbar shared across all pages
- `partials.html` contains the navbar markup.
- `main.js` injects it into `<div id="navbar"></div>`.
- **Do not copy/paste nav into each page**; only modify `partials.html`.

### C) Base path compatibility (GitHub Pages + local dev)
`main.js` detects:
- GitHub Pages base prefix: `/macUSB`
- Local server base prefix: `''`
It sets `basePrefix` and loads partial:
- `${basePrefix}/pages/partials.html`
In partial HTML, use `{{BASE}}` placeholder where needed, then replace in JS:
- `html.replaceAll('{{BASE}}', basePrefix)`

### D) GitHub API fetch (Latest release)
- `main.js` fetches latest release tag from:
  `https://api.github.com/repos/Kruszoneq/macUSB/releases/latest`
- Writes to `#latest-version` as: `Latest version: <tag>`

### E) Landing screenshots carousel
- Carousel lives inside the hero on desktop: `.hero-media .screenshot-stage` (left column).
- `.screenshot-stage` uses images with `data-step` ordering.
- Carousel auto-advances with IntersectionObserver (starts when visible).
- Do not remove; do not break ordering logic.
- The `#screenshots` section below the hero uses items with a left screen + right description layout; on small screens the description stacks under the screen.
- Screens in the `#screenshots` section are zoomable via the existing lightbox; use `class="zoom-image"`.

### F) Theme detection + manual toggle
- Stored in localStorage under key: `macusb-theme` (`auto|light|dark`)
- Default is `auto`.
- Toggle is in navbar (right side).
- Theme changes must be smooth (transition variables).

### G) Guides dropdown
- “Guides” uses a dropdown with groups:
  - **macUSB**
    - Tiger Multi-DVD
  - **PowerPC**
    - PowerPC USB Boot
- Dropdown must be usable:
  - Hover on desktop fine pointers
  - Click on touch/mobile
  - Keyboard accessible (Enter/Space/ArrowDown, Escape)

### H) Scroll cue (hero)
- The down-arrow button in the hero scrolls to `#screenshots`. Keep the anchor ID and smooth-scroll behavior.

---

## 5) Navbar Information Architecture

Top-level nav should include:
- GitHub link
- About
- Guides dropdown (grouped headings)
- Theme toggle button

Guides dropdown style:
- Group titles are uppercase, small, subtle, like Apple Docs.
- Links are under groups (not tag pills).

---

## 6) Guides Pages: Content & UX Rules

General:
- Apple Docs-like tone: direct, procedural, user-focused (“you”).
- Do not shorten critical procedures (must match source instructions).
- Use strong scannability: clear H2 sections, short lead, minimal fluff.
- Screenshots:
  - Smaller, consistent max sizing:
    - max-width: 700px
    - max-height: 640px
  - Click-to-zoom enabled (`img.guide-image` + lightbox).
  - Add subtle “Click to zoom” hint overlay on hover (desktop only).

SEO:
- Each guide should include:
  - `<title>` with strong long-tail keywords
  - `<meta name="description">`
  - `canonical` URL
  - OG tags (title/description/image when applicable)
- Use meaningful headings and section ids.

### A) PowerPC USB Boot guide
File: `/pages/guides/ppc_boot_instructions.html`
- Title and H1:
  **PowerPC USB Boot — Open Firmware Instructions**
- Lead:
  concise and functional.
- Prerequisites:
  1) Wired USB keyboard.
  2) macUSB-created installer USB drive (reliable booting) + mention Multi-DVD supported.
- Callout includes link to Tiger Multi-DVD guide.
- No TOC on this page (too short); do not reintroduce TOC unless page grows significantly.

### B) Tiger Multi-DVD guide
File: `/pages/guides/multidvd_tiger.html`
- Has TOC + autogen + scrollspy.
- Steps include:
  - Files you’ll need (includes screenshot 01-files.png)
  - Single-DVD edition (02-cd1.png)
  - Multi-DVD workflow and forced detection (03/04/05/06)
  - During installation: switching discs (critical note)
  - “Additional notes for PowerPC Macs” section linking to PowerPC boot guide (07-finish.png)
- Keep narrative consistent: addressed to reader, clear and direct.
- TOC is auto-generated by JS and highlights current section; must remain stable.

---

## 7) Content Conventions (Microcopy)

Preferred tone:
- Clear, calm, Apple-like.
- Avoid “on the application’s website” phrasing inside the website itself.
- Use “available here” / “see the guide” / “detailed instructions are available here”.

Buttons:
- “Download macUSB” with download icon.

About page:
- No “Installation and first run” section.
- “What you get” includes a Security card noting notarization starting with v1.1.2.
- PowerPC booting guide link is a button inside the “PowerPC revival” card.
- “PowerPC revival” spans full width in the “What you get” grid.

Footnotes:
- Apple Docs-style superscripts (no pill backgrounds).
- Footnote 3 on About page links to Tiger Multi-DVD guide with phrasing:
  “The Single DVD edition is recognized automatically. Detailed instructions for the Multi-DVD edition are available here: Tiger Multi-DVD Guide.”

---

## 8) Implementation Notes / Gotchas

- Always include `<div id="navbar"></div>` near top of body.
- Always include `main.js` with correct relative path:
  - index: `/assets/js/main.js`
  - pages: `../assets/js/main.js`
  - guides: `../../assets/js/main.js`
- Same for CSS path.
- Prefer minimal inline styles. If necessary, migrate to `style.css`.
- `main.js` updates `--vh` and `--nav-height` CSS variables; the landing hero relies on these for full-viewport sizing and spacing.

Hover “delay” bugs:
- Avoid pointer-event traps that keep hover active after mouse leaves.
- Dropdown hover-bridge should only capture pointer events when dropdown is open/hovered.

---

## 9) Development Workflow

Local server:
- Serve from repo root.
- Ensure links work without forced `/macUSB` prefix.
- `main.js` basePrefix logic must stay intact.

When making changes:
- Do not regress:
  - nav scroll animation
  - GitHub release fetch
  - theme toggle and transitions
  - dropdown usability
  - screenshot carousel
  - guide image zoom
  - canonical/meta tags

---

## 10) Next Planned Work (Roadmap)

- “Guides” may expand in the future (more items).
- PPC boot guide can grow; if it becomes longer, reconsider TOC.
- Possible future guide: “Multi-DVD creation with screenshots” already added (Tiger).
- Ensure SEO scalability: consistent titles and meta descriptions.

---

## 11) Acceptance Checklist (for any change)

Before shipping:
- [ ] Navbar appears on index + about + all guides.
- [ ] Guides dropdown works on desktop hover and mobile click.
- [ ] Theme toggles smoothly; dark uses #303030 background.
- [ ] Scrolled nav becomes frosted and remains readable in dark mode.
- [ ] Latest version text loads from GitHub API.
- [ ] Landing hero fits viewport without weird offsets.
- [ ] Screenshots carousel works in the hero and stays aligned with the hero content height.
- [ ] #screenshots section shows placeholder (no carousel duplication).
- [ ] Guide screenshots are not oversized; click-to-zoom works.
- [ ] No broken relative links (local + GitHub Pages).
- [ ] Meta tags present for guides (title/description/canonical/OG).

---

## 12) Changelog

- 2026-01-24: Added meta rules for maintaining this document, documented the hero split layout, scroll cue behavior, and CSS variable dependencies for viewport sizing.
- 2026-01-24: Documented the screenshots section placeholder layout and the position of the feature cards above it.
- 2026-01-24: Updated screenshots section to use three real app screenshots with a section title.
- 2026-01-24: Moved the screenshots title below the feature cards and enabled click-to-zoom for the landing screenshots.
