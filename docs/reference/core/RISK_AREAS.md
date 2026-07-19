# Delicate Areas and Known Risks

Keep this file current with operational hotspots that can cause regressions.

## High-Risk Areas

- Version/compatibility heuristics with many special cases.
- USB formatting and APFS-to-physical-store mapping.
- Helper registration/signing/environment drift causing late-stage failures.
- Windows BIOS raw writes to MBR boot-code bytes and the post-MBR gap; artifact pinning, layout validation, write ordering, synchronization, and readback must stay aligned.
- Cancellation races at the non-cancellable macUSBoot boundary; a rejected helper request must never clear app handlers or produce a cancelled result.
- Localization key drift between helper emissions and app rendering.
- Notification/permission UX divergence across startup/menu/finish paths.
- Cross-feature leakage between downloader, analysis, and USB creation.

## Mitigation Pattern

For any change in a high-risk area:
- isolate scope,
- run targeted smoke validation,
- verify unrelated feature behavior was not touched,
- update corresponding reference docs.
