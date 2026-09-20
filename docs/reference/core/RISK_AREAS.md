# Delicate Areas and Known Risks

Keep this file current with operational hotspots that can cause regressions.

## High-Risk Areas

- Version/compatibility heuristics with many special cases.
- Physical host architecture and local Mach-O slice detection: process architecture is not authoritative when macUSB runs under Rosetta; CoreFoundation architecture results must be normalized consistently, and unknown `createinstallmedia` formats must fail closed.
- Rosetta installation through the privileged helper: license confirmation, fixed executable/arguments, one-task exclusion, pipe draining, and bounded post-install probes must remain aligned.
- USB whole-disk enumeration, Option-volume parent matching, workflow-driven selection normalization, and destructive target formatting.
- Helper registration/signing/environment drift causing late-stage failures.
- Windows BIOS raw writes to MBR boot-code bytes and the post-MBR gap; artifact pinning, layout validation, write ordering, synchronization, and readback must stay aligned.
- Cancellation races at the non-cancellable macUSBoot boundary; a rejected helper request must never clear app handlers or produce a cancelled result.
- Localization key drift between helper emissions and app rendering.
- Notification/permission UX divergence across startup/menu/finish paths.
- Cross-feature leakage between downloader, analysis, and USB creation.
- Old Yosemite–Catalina installers may still fail after Rosetta removes `EBADARCH`; Rosetta availability is a prerequisite, not a guarantee of complete legacy installer compatibility.
- Termination during privileged or destructive work can leave media, mounts, or temporary data in an indeterminate state; every new long-running operation must acquire and release an active-operation token on all terminal paths.
- A helper cancellation acknowledgement is not a terminal workflow result. App-side USB and helper tokens remain active until the helper sends the final result or the XPC connection is invalidated.
- Helper process exit is gated by both client-connection and privileged-operation leases. App crash or Force Quit may request cancellation, but the daemon must not exit during a non-cancellable safety-critical stage.

## Mitigation Pattern

For any change in a high-risk area:
- isolate scope,
- run targeted smoke validation,
- verify unrelated feature behavior was not touched,
- update corresponding reference docs.
- verify both `Command-Q` and main-window close during every newly protected operation.
