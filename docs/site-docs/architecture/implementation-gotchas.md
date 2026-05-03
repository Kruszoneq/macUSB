# Implementation Notes and Gotchas

## Required asset path prefixes

- `index.html`: use `assets/...`
- pages in `/pages`: use `../assets/...`
- guides in `/pages/guides`: use `../../assets/...`

## Runtime CSS variables from JS

`assets/js/core/partials-nav-footer.js` updates:
- `--vh`
- `--nav-height`
- `--page-header-offset`

## Script loading strategy

- Keep script loading page-scoped.
- Do not reintroduce one monolithic JS runtime file for all pages.
- Prefer loading only features required by the current page.

## Editing constraints

- Avoid inline styles unless absolutely necessary.
- Do not replace partial injection with static copied navbar/footer markup.
