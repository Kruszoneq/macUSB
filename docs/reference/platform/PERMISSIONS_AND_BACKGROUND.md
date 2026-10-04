# Permissions and Background Contract

## Runtime Prerequisites

The app requires:
- Full Disk Access for `macUSB`,
- Allow in the Background approval for helper operation.

Startup and helper readiness flows must surface missing prerequisites.

## Current Runtime Behavior

- Full Disk Access is checked without reading either the user or system TCC database.
- The check uses non-destructive access probes against resources protected by Full Disk Access:
  - `/Library/Preferences/com.apple.TimeMachine.plist` is the primary file probe,
  - the current user's Mail, Messages, Safari, and HomeKit Library directories are fallback directory probes when the primary result is inconclusive.
- Probe results use three internal states:
  - `granted` only after a protected read or directory listing succeeds,
  - `denied` when TCC returns `EPERM`,
  - `unknown` for missing resources, ordinary POSIX access errors, and other inconclusive failures.
- Only `granted` maps to `MenuState.hasFullDiskAccess = true`; both `denied` and `unknown` keep the existing missing-permission alert and warning behavior.
- Full Disk Access is checked during startup, app activation, installation-summary refresh, and immediately before opening its System Settings panel.
- The pre-settings check acts as a best-effort registration probe so macOS can add macUSB to the Full Disk Access list before the user enables it.
- The Full Disk Access panel uses the current System Settings deep link for supported macOS versions, with the existing general System Settings fallback if the deep link cannot be opened.
- Helper background approval is checked at startup and in ensure-ready/repair flows.
- The registered LaunchDaemon runs on demand: startup readiness opens and retains an XPC connection for the lifetime of the app instead of relying on `RunAtLoad`.
- Normal app termination explicitly invalidates the XPC connection. A crash or Force Quit is detected by the helper through XPC connection loss.
- After the final client disconnects, the helper cancels cancellable work and exits once no privileged operation remains. Non-cancellable safety-critical work reaches its terminal state before exit.
- The helper remains registered and approved while its process is stopped, so the next app launch can start it through the Mach service without repeating approval.
- Downloader presentation and app reactivation passively refresh Full Disk Access, helper service approval, and XPC health without registering or repairing the helper.
- Downloader discovery remains available with missing prerequisites, but a download session cannot start until Full Disk Access and helper readiness are confirmed.
- Downloader prerequisite alerts use the current System Settings terminology `Aktywność aplikacji w tle` / `App Background Activity` and open the corresponding settings panel directly.
- Missing prerequisites are visible and can block reliable helper operations.
- External drive support defaults to disabled on launch/termination unless explicitly enabled.

## Optional Automatic Welcome Transition

- `Options → Automatically skip the welcome screen` is disabled by default. `MenuState.skipWelcomeEnabled` stores the choice under the stable `SkipWelcomeScreenV1` UserDefaults key; startup, termination, and app-version changes do not reset it.
- `WelcomeStartupCoordinator` owns one startup sequence per app session, independently of Welcome view recreation: Full Disk Access prompt, helper bootstrap including any version/build-driven auto-repair, notification-state refresh without prompting, and app-update check.
- The welcome screen remains visible during this preparation. Automatic navigation uses the same analysis destination as the manual Start button.
- Navigation requires successful helper bootstrap/auto-repair, a successful update response confirming no newer version, confirmed Full Disk Access, and a fresh passive helper status/XPC health check. Denied or unknown access and missing background approval block it.
- Network/HTTP failures, invalid update metadata or app version, any newer app version (even after Ignore), and failed helper bootstrap/auto-repair block automatic navigation for that session. The manual Start action remains available.
- With the option enabled, permissions and helper health are rechecked after the startup update check. Returning from System Settings, regaining the key window after a dialog, changing the option, or changes in protected-operation activity refresh these prerequisites without rerunning bootstrap or the update request.
- Automatic navigation waits while the app is inactive, a modal window or sheet is open, or any protected operation is active. It happens at most once per launch; manual or automatic navigation consumes the opportunity, so Back and reset do not immediately navigate again.
- This option does not select an image, run analysis, or start USB creation. Existing destructive confirmation and notification authorization remain user-initiated.

## Logging and Diagnostics

Important startup and helper-approval milestones are logged via `AppLogging`.
Full Disk Access checks log:
- the check trigger,
- every executed probe identifier, operation, and path,
- success or the captured POSIX `errno` and description,
- each probe signal and the final aggregate status.

These check and probe lines use English messages with the `[HH:MM:SS] [PERMISSIONS]` prefix.

Protected file contents are never logged.
Logs should clearly indicate which prerequisite is missing and what the app did next.
The automatic welcome transition records startup blockers, final Full Disk Access/helper readiness, and the actual transition through `AppLogging` under `[APP]`, in English. The transition entry is written immediately before navigation.

## Update Trigger

Update when permission prompts, startup gating order, or background-approval handling changes.
