# macUSB Changelog Rules

This file defines how to write release notes in `CHANGELOG.md`.

## General Rules

- `CHANGELOG.md` should contain release entries only (no writing instructions).
- Write changelogs in English.
- Verify each entry against shipped behavior and `docs/documents/development/DEVELOPMENT.md`.
- Keep wording concise and suitable for GitHub Releases.
- Changes with only marginal product impact do not have to be listed in a release entry.
- Small copy-only edits can be grouped under generic labels such as `Poprawki tłumaczeń` or general text fixes.
- Changelog bullets must stay user-friendly and readable; avoid low-level technical jargon when the change was not significant.

## Release Entry Format

- Release title must contain only the app version, for example:
- `## v2.0`
- `## v2.0.1`
- Start each release with one short summary paragraph describing what the release focuses on.
- Keep the summary as one coherent paragraph.
- For major releases, the preferred section order is: `ADDED`, `CHANGES`, `IMPROVEMENTS`.
- For hotfix/patch releases (for example `x.x.1`), sections are optional when change scope is small.
- Section names are suggestions, not strict requirements; skip unnecessary sections and use better-fitting custom sections when needed.

## Bullet Style

- Keep bullets factual and user-oriented.
- Do not overdescribe implementation internals unless needed for release clarity.
- Do not use file-based screen names (for example class/file names); describe screens functionally (for example selection screen, analysis screen, summary screen).
- When behavior is conditional, state the condition clearly (for example permissions, toggles, runtime state).
- Use consistent menu path formatting: `Options → ...`, `Help → ...`, `Tools → ...`.

## Tone and Scope

- Avoid unverifiable marketing claims.
- Prefer impact-focused wording over low-level technical details.
- Include technical context only when it helps users understand visible behavior changes.
