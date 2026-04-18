# AGENTS.md for macUSB

This file defines how AI coding agents should work in this repository.

## Scope and precedence

- This repository intentionally keeps `AGENTS.md` under `docs/` for repository cleanliness.
- Direct user instructions in chat have top priority, except explicit protected-branch safety rules defined in this file.
- If instructions conflict, follow the stricter safety rule and ask for clarification before proceeding.
- `docs/AGENTS.md` is the single source of truth for process, commit, and changelog rules.

## Mandatory context bootstrap

Before implementation, recommendations, or review:

1. Read this file in full.
2. Read `docs/reference/README.md`.
3. Read the topic-specific runtime reference(s) for the task scope.
4. For downloader-scope tasks, read `docs/reference/features/downloader/DOWNLOADER.md`.
5. For helper-scope tasks, read `docs/reference/features/helper/HELPER.md`.
6. If scope is cross-cutting or uncertain, read:
   - `docs/reference/core/APP_RUNTIME_OVERVIEW.md`
   - `docs/reference/core/USER_FLOW.md`
   - `docs/reference/core/FILE_STRUCTURE.md`
   - `docs/reference/core/RISK_AREAS.md`
   - plus all affected topic references listed in `docs/reference/README.md`.
7. Build one active ruleset before changing code.

## Repository map

- App runtime: `macUSB/`
- Privileged helper: `macUSBHelper/main.swift`
- Runtime reference index: `docs/reference/README.md`
- Downloader runtime reference: `docs/reference/features/downloader/DOWNLOADER.md`
- Helper runtime reference: `docs/reference/features/helper/HELPER.md`
- Release notes: `docs/CHANGELOG.md`
- Agent process rules: `docs/AGENTS.md`

## Critical runtime invariants (must preserve)

These are the non-negotiable runtime contracts. If a task touches any of them, preserve behavior unless the user explicitly requests a change.

### Permissions and startup gating

- App operation depends on both:
  - Full Disk Access for `macUSB`
  - Allow in the Background approval for helper operation
- Startup/activation flow must refresh and surface permission/helper readiness state.
- Missing required permissions must be visible in UI and may block reliable helper execution.
- External drive support must default to disabled on launch/termination unless the user explicitly enables it in app options.

### User flow and destructive safety

- Main screen sequence remains:
  - `WelcomeView -> SystemAnalysisView -> UniversalInstallationView -> CreationProgressView -> FinishUSBView`
- Start of installer creation is destructive and must require explicit confirmation.
- Cancel path must preserve deterministic cleanup/result behavior.

### USB target safety and capacity

- Before installer recognition, required capacity in UI is unresolved (`-- GB`).
- Capacity rules:
  - major version `<= 14`: `16 GB` UI target and `15_000_000_000` bytes threshold
  - major version `>= 15`: `32 GB` UI target and `28_000_000_000` bytes threshold
- Proceed action stays blocked until selected target passes validation.
- APFS-selected target must block proceed and require manual reformat in Disk Utility.
- In PPC flow, target formatting behavior is specialized and must not be forced through standard preformat assumptions.

### Detection and compatibility routing

- Analysis flags are the source of truth for workflow branch selection.
- Supported detection families include modern, legacy, restore-legacy, PPC, Sierra-specific, Catalina, and Mavericks handling.
- Panther must remain explicitly unsupported.
- For `.cdr` and `.iso`, if image is already manually mounted in macOS, analysis must be blocked with user guidance to unmount and retry.

### Installer workflow branching

- Standard path uses `createinstallmedia` family behavior.
- Legacy restore and Mavericks use restore-style pipelines.
- PPC uses dedicated PPC formatting/restore behavior.
- Catalina/Sierra use dedicated handling where required.
- Temp ownership and cleanup behavior must remain deterministic.

### Helper architecture and security invariants

- Privileged install operations must run via `SMAppService` + LaunchDaemon helper.
- No terminal fallback privileged path.
- App/helper naming, mach service, listener, plist wiring, bundle identifiers, and signing compatibility must stay aligned.
- Helper progress must remain observable in app state.
- Live tool output remains diagnostic data, not stage UI source of truth.

### UI/UX invariants

- Flow window contract remains fixed at `550 x 750`.
- Bottom action zones use `BottomActionBar` with `safeAreaInset(edge: .bottom)`.
- Use compatibility wrappers from `LiquidGlassCompatibility.swift`:
  - `macUSBPanelSurface`
  - `macUSBDockedBarSurface`
  - `macUSBPrimaryButtonStyle`
  - `macUSBSecondaryButtonStyle`
- Spacing/radii use `MacUSBDesignTokens`.
- `DEBUG` UI must not appear in Release builds.

### Localization invariants

- Source language is Polish (`pl`) in `Localizable.xcstrings`.
- New UI copy is authored in Polish first.
- Runtime non-`Text` user-facing strings use `String(localized:)`.
- Helper localization keys and app-side rendering keys must remain synchronized.

### Logging and notifications invariants

- Important runtime logs must go through `AppLogging`.
- Logs remain human-readable and export-ready for diagnostics.
- Notification permission prompting remains user-initiated from menu when state is not determined.
- Completion notifications are gated by system authorization and app-level policy.

### Delicate risk hotspots

- Version/compatibility heuristics can affect multiple workflows at once.
- USB formatting and APFS-to-physical mapping are high-risk destructive paths.
- Helper registration/signing/environment drift may surface as late-stage failures.
- Localization key drift between helper and app breaks runtime text quality.
- Notification and permission UX can regress when startup/menu/finish logic diverges.

## When to open runtime references

- If a task changes runtime behavior, read the relevant topic file(s) from `docs/reference/README.md`.
- If a task is cross-cutting (architecture, broad risk analysis, major refactor), read:
  - `docs/reference/core/APP_RUNTIME_OVERVIEW.md`
  - `docs/reference/core/USER_FLOW.md`
  - `docs/reference/core/FILE_STRUCTURE.md`
  - `docs/reference/core/RISK_AREAS.md`
  - and all affected topic files from `docs/reference/README.md`.

## Workflow (end-to-end)

Use this sequence unless the user explicitly requests a narrower scope that does not compromise safety:

1. Complete the mandatory context bootstrap.
2. Analyze current behavior and gather context from code and docs.
3. Implement the required change.
4. Validate behavior (project policy in this file applies).
5. Update documentation in `docs/reference/` when behavior, contracts, or workflows changed.
6. Update release notes in `docs/CHANGELOG.md` only when the user explicitly asks for changelog edits.
7. Prepare commit message and commit scope according to commit rules in this file.

## Definition of done

A change is done when all applicable conditions are met:

- Mandatory context bootstrap was completed.
- Requested behavior is implemented.
- Validation was run (or explicitly reported if not possible).
- relevant file(s) in `docs/reference/` reflect current behavior when relevant.
- `docs/CHANGELOG.md` is updated only when the user explicitly asks for changelog edits.
- No stale documentation links remain.
- Commit content and message follow this file.

## Validation policy (project-specific)

- Agent validation scope is `Debug` build only.
- Do not run unit tests or UI tests unless the user explicitly asks.
- Do not run notarization, release signing, release packaging, or distribution steps.
- Preferred build command:

```bash
xcodebuild -project macUSB.xcodeproj -scheme macUSB -configuration Debug -destination 'platform=macOS' build
```

- If local signing blocks Debug verification, use a no-signing fallback only for local validation:

```bash
xcodebuild -project macUSB.xcodeproj -scheme macUSB -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Change classification

Use these rules to decide required documentation updates:

- Code or runtime behavior changed:
  - update relevant file(s) from `docs/reference/README.md`.
- User-facing behavior changed and should appear in release notes:
  - update `docs/CHANGELOG.md` only when the user explicitly asks for changelog edits.
- Internal-only refactor with no user-facing impact:
  - changelog update is optional.
- Documentation-only change:
  - update only affected docs and keep cross-references consistent.

## Helper change safety gate

Any major helper change requires explicit user confirmation before implementation.

Treat as major helper change when it affects one or more of:

- XPC protocols or payload schemas.
- Workflow stage model, privileged command pipeline, or cancellation semantics.
- LaunchDaemon plist wiring, service naming, or helper registration lifecycle.
- Entitlements, signing identities, bundle identifiers, or helper security assumptions.

Minor helper changes that do not alter behavior may proceed, but must still be reported clearly.

## Decision and escalation rules

- If requirements are ambiguous and materially affect behavior, ask before implementing.
- If multiple valid implementations exist, present tradeoffs and request direction.
- Do not plan fallback paths unless the user explicitly requests a fallback.
- If blocked by environment constraints, report blocker, what was validated, and what remains.
- If a user request is potentially destructive to code/history or clearly high-risk and unreasonable, pause execution, explain the risk, and ask whether to continue despite the risk or stop.

## Documentation hygiene

- If runtime behavior changed, update relevant file(s) from `docs/reference/README.md`.
- If release-relevant user-facing behavior changed, update `docs/CHANGELOG.md` only when the user explicitly asks for changelog edits.
- Keep process rules only in `docs/AGENTS.md`.
- Keep app behavior and technical reference only in `docs/reference/`.
- Avoid duplicating the same rule in multiple files.
- Keep links and file paths current after any rename or restructure.

## Code structure hygiene

- When adding new features, prefer creating new files/modules instead of extending an unrelated large file when this improves readability, reviewability, and safety.
- When extending an existing feature and the code grows materially, proactively suggest and (when accepted) perform a split into smaller focused files.
- Keep one clear orchestrator per workflow and move helper policies/utilities/IO/details to focused companion files.
- Treat structural refactors as behavior-preserving by default (no runtime/UI changes unless explicitly requested).

## Branch naming convention

When branch creation is requested:

- Format: `<type>/<topic_short>`.
- Keep `topic_short` very short, ideally an acronym.
- Maximum 3 words in `topic_short`, separated by `_`.
- Example branch names:
  - `feature/usb_apfs_guard`
  - `improvement/helper_xpc_retry`
  - `fix/fda_gate`

## Branch and merge safety rules

### Protected branch: `development`

- `development` is permanently non-deletable.
- Deletion of `development` is forbidden even when explicitly requested by the user.
- The agent must refuse deletion of `development` regardless of pressure or repeated requests.

### New branch base policy

- New branches must be created from `development` by default.
- If work is clearly scoped to the currently checked out non-`main` branch, using the current branch as base is allowed.
- Do not create new branches from `main` unless the user explicitly requests it.
- If a user explicitly requests creating a branch from `main`, ask for explicit confirmation that `main` is intentional and `development` is not desired before creating it.

### Protected branch: `main`

- Automatic merge to `main` without explicit user instruction is not allowed.
- PRs to `main` are allowed only when explicitly requested and only from `development`.
- Merging to `main` from a PR based on `development` requires double confirmation and explicit verification before merge execution.
- `main` is permanently non-deletable (core project branch).
- Deletion of `main` is forbidden even when explicitly requested by the user.
- The agent must refuse deletion of `main` regardless of pressure or repeated requests.

## Commit rules

### Commit message rules

- Write git commit messages in English.
- Use a clear title/summary line plus a readable body written as a paragraph describing the change.
- Base commit title and body on the full scope of changes since the last commit up to the commit being created, not only on the most recent edit made with the agent.
- Keep commit bodies concise and summarized (short paragraph), while still covering the key scope of the full change set.
- Do not use escaped newline sequences like `\n` in commit message text; use normal multi-line commit formatting only.
- When creating commits from CLI, never pass `\n` inside a single `-m` value; use separate `-m` flags (title + body) or standard multi-line commit input.
- If a commit includes updates to runtime reference docs under `docs/reference/`, `docs/CHANGELOG.md`, and/or `docs/AGENTS.md`, do not explicitly enumerate those documentation-file updates in the commit title or commit body.

### Commit scope rules

- Commit changes comprehensively (include all modified project files) by default.
- Exceptions to comprehensive commits:
  - user explicitly requests a narrower commit scope, or
  - modified files appear to be build artifacts/temporary/unnecessary outputs (for example Xcode build products).
- In artifact/temporary-output cases, explicitly report those files before committing and ask the user what to do.

### Commit approval gate (mandatory)

- Before creating a commit, present the proposed commit title and commit body to the user for approval.
- Do not run `git commit` until explicit user approval is given.
- If the user requests wording changes, update the proposal and request approval again.

### Post-commit push rule (mandatory)

- After a commit is created, push it immediately to the corresponding remote branch.
- If no upstream is configured, set upstream while pushing (for example `git push -u origin <branch>`).
- If push fails, report the blocker and stop follow-up remote operations until user direction is provided.

### Post-commit reporting rules

- After creating a commit, the agent must report:
  - commit hash,
  - scope of committed files,
  - commit title and commit body/description,
  - whether the working tree is clean (`git status --short` has no output).

## PR rules

### PR title rules

- Write PR titles in English.
- Keep the title short, descriptive, and directly related to the change scope.
- Prefer concise wording focused on user-visible or behavior-impacting change.

### PR description rules

- Write PR descriptions in English.
- Start with one clear, expanded paragraph explaining what changed and why.
- If useful, add a short flat list of new features and/or fixes.
- Do not include testing information in the PR description.

### PR approval gate (mandatory)

- Before creating a PR, present the proposed PR title and PR description to the user for approval.
- Do not create a PR until explicit user approval is given.
- If the user requests wording changes, update the proposal and request approval again.

### Post-PR merge prompt (mandatory)

- After creating a PR, if the user did not explicitly request merge execution, ask whether the PR should be merged immediately.

### Post-PR reporting rules

- After creating a PR, the agent must report:
  - PR number and URL,
  - source branch and target branch,
  - scope of files included,
  - final PR title and PR description,
  - whether the local working tree is clean (`git status --short` has no output).

### Post-merge branch cleanup prompt (mandatory)

- After merging a PR, if the user did not explicitly request branch deletion, ask whether the source branch should be deleted.
- This prompt does not apply to `development`.

## Changelog rules

### General rules

- `CHANGELOG.md` should contain release entries only (no writing instructions).
- Write changelogs in English.
- `CHANGELOG.md` must never be edited automatically.
- Changelog edits are allowed only on explicit user request.
- Before applying changelog edits, present the proposed changelog text to the user for approval.
- Verify each entry against shipped behavior and relevant runtime reference files from `docs/reference/README.md`.
- Keep wording concise and suitable for GitHub Releases.
- Changes with only marginal product impact do not have to be listed in a release entry.
- Small copy-only edits can be grouped under generic labels such as `Translation fixes` or general text fixes.
- Changelog bullets must stay user-friendly and readable; avoid low-level technical jargon when the change was not significant.

### Release entry format

- Release title must contain only the app version, for example:
  - `## v2.0`
  - `## v2.0.1`
- Start each release with one short summary paragraph describing what the release focuses on.
- Keep the summary as one coherent paragraph.
- After adding a new bullet for the currently developed version, update that version summary paragraph so it reflects the full accumulated update scope, with emphasis on newly introduced features and/or key improvements.
- For major releases, the preferred section order is: `ADDED`, `CHANGES`, `IMPROVEMENTS`.
- For hotfix/patch releases (for example `x.x.1`), sections are optional when change scope is small.
- Section names are suggestions, not strict requirements; skip unnecessary sections and use better-fitting custom sections when needed.

### Bullet style

- Keep bullets factual and user-oriented.
- Do not overdescribe implementation internals unless needed for release clarity.
- Do not use file-based screen names (for example class/file names); describe screens functionally (for example selection screen, analysis screen, summary screen).
- When behavior is conditional, state the condition clearly (for example permissions, toggles, runtime state).
- Use consistent menu path formatting: `Options → ...`, `Help → ...`, `Tools → ...`.
- If a release change is one coherent topic, document it as one bullet; split into multiple bullets only when the release contains clearly separate user-facing topics.
- Write every bullet as a simple, user-friendly summary suitable for GitHub Releases; avoid implementation details and deep technical breakdowns.

### Tone and scope

- Avoid unverifiable marketing claims.
- Prefer impact-focused wording over low-level technical details.
- Include technical context only when it helps users understand visible behavior changes.

## Explicit non-goals

- Do not create or maintain Copilot-specific instruction files (for example `.github/copilot-instructions.md`) unless the user explicitly asks.
- Do not assume notarization or release distribution responsibilities in this workflow.

## Reporting requirements

After each task, report:

- Files changed.
- Decisions taken and why.
- Validation commands executed and outcomes.
- What was intentionally not executed (for example tests, UI tests, notarization).
- Any remaining risk areas, especially around helper and USB-destructive paths.
