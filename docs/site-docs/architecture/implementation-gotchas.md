# Implementation Notes and Gotchas

## Required asset path prefixes

- `index.html`: use `assets/...`
- pages in `/pages`: use `../assets/...`
- guides in `/pages/guides`: use `../../assets/...`

## Runtime CSS variables from JS

`main.js` updates:
- `--vh`
- `--nav-height`
- `--page-header-offset`

## Editing constraints

- Avoid inline styles unless absolutely necessary.
- Do not replace partial injection with static copied navbar/footer markup.
