# Delicate Areas and Known Risks

Keep this file current with operational hotspots that can cause regressions.

## High-Risk Areas

- Version/compatibility heuristics with many special cases.
- USB formatting and APFS-to-physical-store mapping.
- Helper registration/signing/environment drift causing late-stage failures.
- Localization key drift between helper emissions and app rendering.
- Notification/permission UX divergence across startup/menu/finish paths.
- Cross-feature leakage between downloader, analysis, and USB creation.

## Mitigation Pattern

For any change in a high-risk area:
- isolate scope,
- run targeted smoke validation,
- verify unrelated feature behavior was not touched,
- update corresponding reference docs.
