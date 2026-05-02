# Page-Level Content Rules

## Homepage (`/index.html`)

Must include:
- Product hero with icon, app name, two-line slogan, primary download CTA, and secondary support CTA.
- Latest version and minimum requirement (`macOS 14.6+`) visible in hero.
- No hero badge.
- Hero intro content should not render visibly before full load; reveal starts after load with the configured intro animation.
- Marketing-first landing structure:
  - product preview,
  - concise "why" message,
  - short value cards,
  - concise "what it creates" statement,
  - open-source trust block with links to repository/support.
- Keep technical deep details out of homepage body; direct users to GitHub for implementation specifics.
- Browser title format: `macUSB - <text>`.

## Legacy About URL (`/pages/about.html`)

- Legacy redirect only.
- Must not contain competing long-form content.
- Required: canonical to homepage, redirect behavior, fallback link.

## Legacy Why URL (`/pages/create-bootable-macos-usb-on-apple-silicon.html`)

- Legacy redirect only.
- Must not contain competing long-form content.
- Required: canonical to homepage, redirect behavior, fallback link.

## Guides

- Preserve procedural clarity and direct language.
- Keep screenshot zoom support.
- Keep Tiger guide TOC auto-generation and scrollspy behavior.
- Cross-guide links must be `card-button` actions:
  - Tiger guide -> PowerPC USB boot instructions
  - PowerPC guide -> Tiger Multi-DVD creation
- Tiger Multi-DVD flow must keep current screenshot narrative:
  - Disc files prepared
  - CD1 detection success
  - CD2+ issue state
  - skip-analysis warning modal
  - forced Tiger recognition state
  - operation details/start screen
  - completion screen with PowerPC instructions link

## Browser title convention

- Homepage: `macUSB - <text>`.
- Every other page: `<text> - macUSB`.
- Do not use `|` or `—` in title patterns.
