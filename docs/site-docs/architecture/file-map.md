# File Map (What Is Used For What)

## Core website files

- `/index.html`: homepage (hero, value, workflow, compatibility).
- `/assets/css/style.css`: visual system and responsive behavior.
- `/assets/js/main.js`: runtime behavior (partials injection, nav state, dropdown, release fetch, carousel, reveal, lightbox, TOC).

## Shared partials

- `/pages/partials.html`: shared navbar (single source of truth).
- `/pages/footer.html`: shared footer (single source of truth).

## Main pages

- `/pages/create-bootable-macos-usb-on-apple-silicon.html`: merged Why/About + SEO page.
- `/pages/about.html`: legacy redirect page to the merged Why page.

## Guides

- `/pages/guides/ppc_boot_instructions.html`: PowerPC Open Firmware boot guide.
- `/pages/guides/multidvd_tiger.html`: Tiger Multi-DVD guide.

## Primary assets

- `/assets/icon/macUSBicon-v2.png`: current icon for nav/favicon/branding.
- `/assets/screenshots/app-v2/*`: app screenshots used on homepage and SEO page.
- `/assets/screenshots/multidvd_tiger/*`: Tiger guide screenshots.

Canonical Tiger screenshot sequence:
1. `01-files.png`
2. `02-cd1.png`
3. `03-cd2.png`
4. `04-info.png`
5. `05-cd2ok.png`
6. `06-creation.png`
7. `07-finish.png`
