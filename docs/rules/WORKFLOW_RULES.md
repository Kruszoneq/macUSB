# macUSB Workflow Rules

This file defines the end-to-end workflow for preparing, documenting, and delivering changes in this repository.

## Purpose

- Keep the change process consistent for all contributors.
- Ensure implementation, documentation, release notes, and commits stay synchronized.
- Serve as the top-level process guide; detailed commit and release-note rules live in dedicated rule files.

## Mandatory Trigger: Automatic Context Bootstrap

This section is mandatory for any AI agent working in this repository.

Trigger condition:
- If this file is referenced by name or path (for example: `WORKFLOW_RULES.md` or `docs/rules/WORKFLOW_RULES.md`), the agent must automatically execute the full bootstrap below before implementation, recommendations, or code review.

Required bootstrap sequence:
1. Read this file in full.
2. Discover every repository file matching `*_RULES.md` and read each one in full.
3. Build one active ruleset from all loaded rules before doing work.
4. Read `docs/reference/APPLICATION_REFERENCE.md` in full.
5. Analyze the full codebase to capture complete technical context:
   - Read all tracked source files and key configuration/build files.
   - Include both app and helper code paths, plus project metadata and operational configs.
6. Start implementation or reporting only after steps 1-5 are complete.

No-skip policy:
- The bootstrap is required even for small changes.
- If any required file cannot be accessed, the agent must stop, report the blocker, and request guidance before proceeding.

## Workflow (End-to-End)

Use this sequence unless the user explicitly requests a narrower scope and that request does not conflict with the mandatory bootstrap:

1. Complete the mandatory context bootstrap.
2. Analyze current behavior and gather context from code and docs.
3. Implement the required change.
4. Validate behavior (build/tests/smoke checks as appropriate).
5. Update documentation in `docs/reference/` when behavior, contracts, or workflows changed.
6. Update release notes in `docs/reference/CHANGELOG.md` when the change is user-facing and release-relevant.
7. Prepare commit message and commit scope according to commit rules.

## Definition of Done

A change is done when all applicable conditions are met:

- Mandatory context bootstrap was completed.
- Requested behavior is implemented.
- Validation was run (or explicitly reported if not possible).
- `docs/reference/APPLICATION_REFERENCE.md` reflects the current behavior when relevant.
- `docs/reference/CHANGELOG.md` is updated when release-relevant.
- No stale documentation links remain.
- Commit content and message follow repository rules.

## Change Classification

Use these rules to decide required documentation updates:

- Code or runtime behavior changed:
  - update `docs/reference/APPLICATION_REFERENCE.md`.
- User-facing behavior changed and should appear in release notes:
  - update `docs/reference/CHANGELOG.md`.
- Internal-only refactor with no user-facing impact:
  - changelog update is optional.
- Documentation-only change:
  - update only the affected doc(s), and keep cross-references consistent.

## Commit Workflow

- Apply commit rules from `docs/rules/COMMIT_RULES.md`.
- Keep commit scope aligned with the requested task scope.

## Release Notes Workflow

- Apply release-note rules from `docs/rules/CHANGELOG_RULES.md`.
- Keep entries short, user-facing, and grouped by coherent topics.

## Decision and Escalation Rules

- If requirements are ambiguous and materially affect behavior, ask before implementing.
- If multiple valid implementations exist, present tradeoffs and request direction.
- If blocked by environment constraints, report blocker, what was validated, and what remains.

## Documentation Hygiene

- Keep process rules only in `docs/rules/`.
- Keep app behavior and technical reference only in `docs/reference/`.
- Avoid duplicating the same rule in multiple files.
- Keep links and file paths current after every rename/restructure.
