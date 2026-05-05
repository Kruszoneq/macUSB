# Landing Page Specification

## Scope

This document describes the actual structure, content, and behavior of `index.html`.

## Section Order and Content

1. Hero
- Product: `macUSB`
- Primary line: `Download. Flash. Boot.`
- Secondary line: `The all-in-one USB creator for Mac`
- Actions:
  - `Download for macOS` (GitHub releases)
  - `Download via Homebrew` (reveals command panel)
  - `Support macUSB`
- Utility text:
  - latest release label (`data-latest-version`)
  - requirement: `Requires macOS 14.6 or newer`
- Scroll cue jumps to `#screenshots`

2. USB Creation (`#screenshots`)
- Kicker: `USB Creation`
- Heading: `Zero-config bootable USB creation`
- Lead: `Select an image and a target drive. macUSB fully automates the drive preparation and image flashing.`
- Note: `The optimal flashing method is applied dynamically based on the source image format.`
- Carousel screenshots:
  - `assets/screenshots/app-v2/01-welcome.png`
  - `assets/screenshots/app-v2/02-analysis.png`
  - `assets/screenshots/app-v2/03-overview.png`
  - `assets/screenshots/app-v2/04-progress.png`
  - `assets/screenshots/app-v2/05-finish.png`

3. macOS Downloader (`#downloader`)
- Kicker: `macOS Downloader`
- Heading: `Pull official macOS installers straight from Apple`
- Lead: `Skip third-party mirrors. Select a release and download verified, official macOS installers directly within the app.`
- Note: `Track real-time progress and eliminate the need for external tools.`
- Carousel screenshots:
  - `assets/screenshots/downloader/01-installer-list.png`
  - `assets/screenshots/downloader/02-download-progress.png`
  - `assets/screenshots/downloader/03-download-summary.png`

4. Linux Support (`#linux-support`)
- Kicker: `Linux Support`
- Heading: `Smart Linux distro validation`
- Lead: `Drop an ISO to instantly verify the exact OS release and system architecture before flashing.`
- Note: `Visual confirmation prevents accidental flashing of incorrect versions or unsupported architecture images.`
- Carousel screenshots:
  - `assets/screenshots/linux/01-debian.png`
  - `assets/screenshots/linux/02-ubuntu.png`
  - `assets/screenshots/linux/03-mint.png`
  - `assets/screenshots/linux/04-opensuse.png`
  - `assets/screenshots/linux/05-kali.png`
  - `assets/screenshots/linux/06-gentoo.png`

5. Legacy macOS (`#why`)
- Kicker: `Legacy macOS`
- Heading: `Bypass Apple Silicon restrictions`
- Copy: `Creating older macOS installers on Apple Silicon frequently fails due to expired certificates. macUSB automatically handles the validation errors to guarantee a successful flash.`

6. Native App (`#native-performance`)
- Kicker: `Native App`
- Heading: `Built natively with Swift`
- Copy: `No Electron, no web wrappers. macUSB is a lightweight, natively compiled application designed exclusively for macOS, with blazing-fast performance, minimal memory footprint, and tight system integration.`

7. Open Source (`#open-source`)
- Kicker: `Open Source`
- Heading: `Fully open, always free`
- Copy: `macUSB is open source and free. Explore the code on GitHub, report issues, and help shape upcoming releases.`
- CTA: `View on GitHub` -> `https://github.com/Kruszoneq/macUSB`

## Carousel Behavior Rules

Defined by `assets/js/home/carousels.js`.

- Every `.screenshot-carousel` initializes independently.
- Slides are sorted by numeric `data-step`.
- Dots are sorted by numeric `data-step` and reflect active state with:
  - class `is-active`
  - `aria-pressed="true|false"`
- Initial slide is always index `0`.
- Autoplay interval: `2000ms`.
- Manual dot click:
  - navigates to selected slide
  - pauses autoplay for `7000ms`
  - then resumes autoplay
- If `prefers-reduced-motion: reduce` is enabled:
  - static initial slide only
  - no autoplay transitions
- Viewport behavior:
  - starts autoplay when visible (`IntersectionObserver`, threshold `0.3`)
  - stops autoplay when not visible

## Runtime Dependencies

`index.html` must include:

- `assets/js/core/partials-nav-footer.js`
- `assets/js/core/scroll-top-reload.js`
- `assets/js/home/intro-reveal.js`
- `assets/js/home/homebrew-toggle.js`
- `assets/js/home/scroll-cue.js`
- `assets/js/common/reveal.js`
- `assets/js/home/carousels.js`
- `assets/js/common/release-fetch.js`

## Change Management Rule

If landing copy, section order, or carousel behavior changes, update this document in the same change set.
