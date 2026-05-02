# Shared Partials and Base Path

## Shared partial injection

Primary content pages must use:
- `<div id="navbar"></div>`
- `<div id="footer"></div>`

`main.js` injects:
- `${basePrefix}/pages/partials.html`
- `${basePrefix}/pages/footer.html`

Do not copy navbar/footer markup directly into each page.

Exceptions: `/pages/about.html` and `/pages/create-bootable-macos-usb-on-apple-silicon.html` are minimal legacy redirects and intentionally do not mount shared partials.

## Base path compatibility

`main.js` must support both:
- Local dev base path: `''`
- GitHub Pages base path: `/macUSB`

In partials, keep `{{BASE}}` placeholders and replace them via JS.
