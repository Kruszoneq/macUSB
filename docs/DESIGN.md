# macUSB Design Rules

## Purpose

This document defines visual and UX rules for macUSB pages.
It describes how interfaces should look and behave, not what exact marketing copy they contain.

## Visual Direction

- Keep a clean, restrained product-marketing style.
- Use real product screenshots as primary visual proof.
- Prioritize clarity, hierarchy, and whitespace over decorative elements.
- Preserve consistent visual rhythm between sections.

## Theme System

- Support both light and dark themes across primary pages.
- Theme defaults from `prefers-color-scheme` on first load.
- User-selected theme override must persist in `localStorage`.
- Theme switching is exposed in navbar through the theme toggle.

## Typography

- Display headings use `Manrope`.
- Body and UI text use `Inter`.
- Headlines should use tighter tracking and stronger weight than body text.
- Body text should remain neutral and highly readable.

## Color and Contrast

- Primary CTA style: dark filled button with light text.
- Secondary actions: lighter/outlined treatments.
- Keep sufficient contrast in both light and dark themes.
- Use muted text color for supporting information and notes.

## Layout and Spacing

- Homepage sections should keep large vertical spacing bands.
- Content containers should stay centered with consistent max widths.
- Full-width bands may be used for emphasis sections while preserving internal content width.
- Maintain mobile-first responsiveness with no horizontal overflow.

## Buttons and Action Hierarchy

- `cta-button` is the primary conversion action.
- `card-button` is secondary action style.
- `support-button` is tertiary/support action and must remain visually lower priority than primary CTA.
- Action groups should be visually ordered by priority.

## Section Presentation Rules

- Each major section should combine a clear heading, supporting text block, and either media or action.
- Alternate media/copy placement can be used for scan rhythm.
- Kicker labels should be short, uppercase-style section identifiers.
- Avoid dense multi-column copy blocks in landing sections.

## Screenshot Carousel Rules

- Carousel container uses a framed screenshot stage with preserved image proportions.
- Slides transition with smooth fade/scale behavior when motion is enabled.
- Dots represent slide index and active state.
- Dot interaction must update slide and set a temporary autoplay pause.
- Autoplay should run only when the carousel is in viewport.
- Autoplay should stop when out of viewport.
- Reduced-motion users must get a static initial state without autoplay transitions.
- Images should remain uncropped (`object-fit: contain` behavior in stage).

## Motion and Accessibility

- Motion should be subtle and purposeful.
- Respect `prefers-reduced-motion: reduce` and disable non-essential animation.
- Keep keyboard-accessible controls and visible focus behavior.
- Preserve semantic heading order and meaningful alt text.

## Shared Chrome Rules

- Navbar and footer are shared partials and must not be duplicated per page.
- Shared chrome should remain visually consistent across pages.
- Any visual changes to shared chrome must be reflected in `docs/PARTIALS.md` and this file.

Note: This document was originally derived from the previous Cal-based DESIGN.md and then adapted to the current macUSB website.
