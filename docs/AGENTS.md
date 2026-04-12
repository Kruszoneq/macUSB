# AGENTS Guidelines for macUSB Website (`gh-pages`)

## Project Context

The `gh-pages` branch is the primary source branch for the macUSB application website, created by Kruszoneq. This website serves as both the main product site and a source of additional information and tutorials related to the application.

## Rule Enforcement

- All rules in this file are mandatory and must be followed without exception.
- If a user instruction conflicts with any rule in this file, report the conflict, clearly describe the situation, and ask the user how to proceed before taking action.

## Modular Site Documentation Usage

Use modular documentation from `docs/site-docs/` to minimize unnecessary context loading.

- `docs/site-docs/README.md`: entry point and routing map for all site docs.
- `docs/site-docs/architecture/*`: use for project scope, file responsibilities, and technical structure.
- `docs/site-docs/rules/*`: use for UI/UX rules, behavior contracts, navigation architecture, and per-page content constraints.
- `docs/site-docs/checklists/*`: use before release/final verification.

When handling a task, read only the modules required for that task instead of loading all documentation files.

## Local Development and Rendering Validation

- Do not start a local server on behalf of the user.
- If the user asks for local server setup (or related commands), respond with a copy-ready command in a code block and explicitly state that, according to these rules, the user must run it manually in the terminal for stability and independent execution.
- The provided server command must include the path to the macUSB project folder before starting the server.
- Keep placeholder paths in repository docs for privacy, but when replying to the user, always replace `/path/to/macUSB` with the real current macUSB path and never send the placeholder in the final command.
- Local server command to provide:

```bash
cd /path/to/macUSB && python3 -m http.server 8000 --bind 0.0.0.0
```

## Page Creation Rules

- Use English page file names that follow standard web naming conventions.
- Keep shared page elements in separate files and include/import them where needed.
- When creating new pages, use clear standard naming, place files in the correct folder by page type, and update related documentation files automatically in the same change set.

## Commit Rules

- Before creating any commit, prepare a commit draft for user approval.
- Create the commit only after the user explicitly approves the draft.
- Include all changed files in commits, except files excluded by `.gitignore`.
- The draft must include: title, description, and file list.
- The title must be specific and clear.
- The description must be written as one paragraph in full sentences, without line-break markers like `\n`, and must describe the changes included in that commit.
- After commit approval and commit execution, provide an execution report containing: short commit hash, title, number of files, and URL.
- After creating an approved commit, push the current branch to `origin` immediately.

## Pull Request Rules

- Before creating any pull request, prepare a PR draft for user approval.
- Create the PR only after the user explicitly approves the draft.
- Include all changed files in the PR, except files excluded by `.gitignore`.
- The draft must include: title, description, and file list.
- The title must be specific and clear.
- The description must be written as one paragraph in full sentences, without line-break markers like `\n`, and must describe all changes in the PR based on all commits since the last PR.
- The verification request in this section is addressed to the user; the user confirms results from local server testing on computer and phone before PR draft preparation.
- Test rules before preparing a PR draft: ask the user to verify and confirm rendering on a running local server on both a computer and a phone (without GitHub Pages mode), navbar and footer injection on all relevant pages, latest release fetch behavior, guides dropdown behavior on desktop/mobile/keyboard, guide image zoom behavior, and Tiger guide TOC generation with scrollspy behavior.
- Before preparing the PR draft, ask for user confirmation that all required rendering checks were completed and are working correctly.
- Prepare the PR draft only after the user confirms those checks.
- After PR approval and PR execution, provide an execution report containing: short commit hash, title, file list, and URL.
- After creating the PR, if the user did not explicitly instruct otherwise, propose merging the PR and deleting the old branch, but do not perform either action automatically without explicit user instruction.

## Branch Rules

- Branch names should reflect the feature being added (when a specific feature is provided in the request).
- Propose the branch name for approval first; create the branch only after user approval.
- After creating an approved branch, push it to `origin` immediately and set upstream tracking.

## `gh-pages` Branch Protection Rules

Apply the same rules as for other branches, commits, and PRs, with these stricter requirements:

- Committing directly to `gh-pages` requires double user approval.
- Creating or merging a PR from another branch into `gh-pages` requires double user approval.
- The `gh-pages` branch is non-deletable. Refuse any request to delete it, regardless of instruction.
