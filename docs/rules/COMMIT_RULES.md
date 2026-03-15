# macUSB Commit Rules

This file defines how commits should be created for this repository.

## Commit Message Rules

- Write git commit messages in English.
- Use a clear title/summary line plus a concise body describing key changes.
- Do not use escaped newline sequences like `\n` in commit message text; use normal multi-line commit formatting only.
- When creating commits from CLI, never pass `\n` inside a single `-m` value; use separate `-m` flags (title + body) or standard multi-line commit input.
- If a commit includes updates to `docs/reference/APPLICATION_REFERENCE.md`, `docs/reference/CHANGELOG.md`, and/or `docs/rules/CHANGELOG_RULES.md`, do not explicitly enumerate those documentation-file updates in the commit title or commit body.

## Commit Scope Rules

- Commit changes comprehensively (include all modified project files) by default.
- Exceptions to comprehensive commits:
- user explicitly requests a narrower commit scope, or
- modified files appear to be build artifacts/temporary/unnecessary outputs (for example Xcode build products).
- In artifact/temporary-output cases, explicitly report those files before committing and ask the user what to do.

## Post-Commit Reporting Rules

- After creating a commit, the AI agent must report:
- commit hash,
- scope of committed files,
- commit title and commit body/description,
- whether the working tree is clean (`git status --short` has no output).
