# macUSB Website Docs Index

This folder contains modular documentation for the macUSB website.
Use these files to load only the context needed for a specific task.

`docs/AGENTS.md` remains the mandatory process/rules authority for branch, commit, and PR behavior.

## How to use these docs

1. Read `docs/AGENTS.md` first for mandatory execution rules.
2. Open only the files relevant to the requested change.
3. Prefer targeted modules instead of loading all docs at once.

## Quick routing

- Editing site structure or understanding purpose: `architecture/project-overview.md`
- Finding which file is responsible for what: `architecture/file-map.md`
- Shared navbar/footer or base-path logic: `architecture/shared-partials-and-base-path.md`
- Low-level implementation pitfalls: `architecture/implementation-gotchas.md`
- Visual style, spacing, buttons, motion: `rules/design-system.md`
- Non-negotiable JS/UI behavior contracts: `rules/behavior-contracts.md`
- Navbar and guides dropdown structure: `rules/navigation-ia.md`
- Content requirements for each page: `rules/page-content-rules.md`
- Responsive and accessibility constraints: `rules/responsive-accessibility.md`
- Page creation conventions: `rules/page-creation-rules.md`
- Local server and rendering verification rules: `docs/AGENTS.md` (Local Development and Rendering Validation section)
- Final acceptance before shipping: `checklists/pre-ship-acceptance.md`
