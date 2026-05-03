# File Map (What Is Used For What)

## Core website files

- `/index.html`: primary landing page (hero, USB Creation, macOS Downloader, Why macUSB, What It Creates, Open Source).
- `/assets/css/style.css`: visual system and responsive behavior.

## JavaScript runtime (split by scope)

- `/assets/js/core/theme.js`: theme bootstrap and state management (system preference detection, persisted user override, and runtime theme application).
- `/assets/js/core/partials-nav-footer.js`: shared partial injection (`#navbar`, `#footer`), base-prefix handling, nav state/dropdown behavior, runtime CSS variables.
- `/assets/js/core/scroll-top-reload.js`: reload-only scroll reset behavior.
- `/assets/js/common/reveal.js`: generic reveal-on-scroll animation.
- `/assets/js/common/release-fetch.js`: latest release text update and desktop release CTA URL upgrade to latest `.dmg`.
- `/assets/js/home/intro-reveal.js`: homepage intro timing and nav reveal timing.
- `/assets/js/home/homebrew-toggle.js`: Homebrew command panel and copy action.
- `/assets/js/home/scroll-cue.js`: hero scroll cue jump behavior.
- `/assets/js/home/carousels.js`: homepage screenshot carousel logic (including viewport-aware autoplay and manual pause/resume behavior).
- `/assets/js/guides/lightbox.js`: guide image zoom/lightbox behavior.
- `/assets/js/guides/toc-spy.js`: Tiger guide TOC auto-generation and scrollspy.

## Shared partials

- `/pages/partials.html`: shared navbar (single source of truth).
- `/pages/footer.html`: shared footer (single source of truth).

## Main pages

- `/pages/create-bootable-macos-usb-on-apple-silicon.html`: legacy Why URL redirect to homepage `#why`.
- `/pages/about.html`: legacy About URL redirect to homepage `#why`.

## Guides

- `/pages/guides/ppc_boot_instructions.html`: PowerPC Open Firmware boot guide.
- `/pages/guides/multidvd_tiger.html`: Tiger Multi-DVD guide.

## Primary assets

- `/assets/icon/macUSBicon-v2.png`: current icon for nav/favicon/branding.
- `/assets/screenshots/app-v2/*`: app screenshots used in `USB Creation` section.
- `/assets/screenshots/downloader/*`: downloader screenshots used in `macOS Downloader` section.
- `/assets/screenshots/multidvd_tiger/*`: Tiger guide screenshots.

Canonical Tiger screenshot sequence:
1. `01-files.png`
2. `02-cd1.png`
3. `03-cd2.png`
4. `04-info.png`
5. `05-cd2ok.png`
6. `06-creation.png`
7. `07-finish.png`
