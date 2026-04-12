# Page-Level Content Rules

## Homepage (`/index.html`)

Must include:
- Product hero with icon, headline, subtitle, primary download CTA, and secondary `Support macUSB` CTA.
- Latest version and minimum requirement (`macOS 14.6+`).
- No hero badge.
- Value section.
- Workflow section.
- Compatibility and guide bridge links.
- Browser title format: `macUSB - <text>`.

## Legacy About URL (`/pages/about.html`)

- Legacy redirect only.
- Must not contain competing long-form content.
- Required: canonical to merged page, redirect behavior, fallback link.

## SEO page (`/pages/create-bootable-macos-usb-on-apple-silicon.html`)

- English-only merged product + SEO page.
- Must semantically cover intents equivalent to:
  - how to make a bootable macOS USB
  - create bootable macOS installer on Apple Silicon
  - bootable USB for older macOS versions
  - Tiger/Leopard bootable USB for PowerPC
- Must include metadata: title, description, canonical, Open Graph, Twitter.
- Must include structured data: `SoftwareApplication` and `FAQPage`.
- Must include FAQ block and internal links to guides/releases.
- Copy rule: describe current capabilities only; do not add changelog-style sections such as `What's new`, `Added`, `Changed`, `Improved`.

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
