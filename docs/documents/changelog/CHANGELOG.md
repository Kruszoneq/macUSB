# macUSB Release Changelog

This document stores changelogs for released macUSB versions.
Each release entry must reflect shipped behavior and stay consistent with the current codebase and `docs/documents/development/DEVELOPMENT.md`.

## Changelog Writing Guidelines

- Write changelogs in English.
- Use one clear intro paragraph for each release.
- Keep the intro as one coherent block (not split into disconnected lines).
- Use section order: `ADDED`, `CHANGES`, `IMPROVEMENTS`.
- Keep bullets factual and implementation-based; avoid unverifiable marketing claims.
- When a feature is conditional, state the condition explicitly (for example permissions, toggles, runtime state).
- Use consistent menu path formatting in release notes: `Options → ...`, `Help → ...`, `Tools → ...`.
- Keep naming consistent with the app and documentation (for example `SMAppService`, `Liquid Glass`, system version names).
- Before publishing, verify that entries match actual implemented behavior and `DEVELOPMENT.md`.

---

## v2.0

macUSB v2.0 introduces a refreshed interface with full support for the **Liquid Glass** effect, tailored to the modern macOS Tahoe aesthetic, and a new architecture powered by native system services that improves reliability and streamlines the installer media preparation process.

### ADDED
- Native privileged helper tool (**SMAppService**) to handle the installer creation process, ensuring higher stability and removing the need for external terminal sessions.
- Automatic USB media verification and preparation — the app now checks partition schemes and disk formats, converting them to GPT and Mac OS Extended (Journaled) if necessary.
- Interactive progress dashboard — a new screen displaying the status of all steps (pending, in progress, and completed).
- USB standard identification mechanism with low-bandwidth warnings for USB 2.0 devices.
- Real-time USB write speed indicator displayed during the creation process.
- Dynamic system icons extracted directly from the source files of the selected macOS version.
- System notifications for process completion (optional via **Options → Notifications**; delivered when system permission is granted and app-level notifications are enabled).
- Audio feedback signal played upon successful completion of the installer.
- Total operation time summary shown on the final success screen.
- Enhanced logging system covering file analysis and media preparation stages, including data export via **Help → Export diagnostic logs…**.
- Disk Utility shortcut located in the **Tools → Open Disk Utility** menu.
- Expanded language support: Italian, Ukrainian, Vietnamese, and Turkish.

### CHANGES
- The language selection menu has been moved to the menu bar under **Options → Language**.

### IMPROVEMENTS
- Refined visual interface with the Liquid Glass effect, tailored to the macOS Tahoe aesthetic.
- Language switching now updates in-app UI immediately; full menu/system-localized UI refresh may require app restart.
- Added the ability to revert to automatic language detection after a manual override.
- Optimized the recognition engine for Mac OS X 10.4 Tiger to improve source image detection.
- General UI text refinements and localization fixes.

---

## v1.1.2

**macUSB is now officially notarized by Apple!** This milestone confirms the application is safe to use and ensures a seamless installation experience on macOS, eliminating the need to bypass Gatekeeper warnings.

### DISTRIBUTION
- The application is now officially notarized by Apple, ensuring a secure installation without system warnings.
- Distribution format changed to `.dmg` disk image. To update, simply drag macUSB to your Applications folder.

### ADDED
- Added links in the system menu (Help) directing to the official website and bug reporting page (GitHub Issues).

### IMPROVED
- Added a warning message when selecting the OS X Mavericks installer, advising on potential issues when using images from sources other than "Mavericks Forever".
- Updated the PowerPC booting instruction link (shown after creating Tiger or Leopard USBs) — it now redirects directly to the guide on the application's website.

---

## v1.1.1

This release expands installer compatibility with OS X Mavericks and introduces optional support for external HDD/SSD targets.

### ADDED
- Support for OS X Mavericks installer.
- Support for external drives (HDD/SSD).

---

## v1.1

In this release, macUSB expands support for additional legacy macOS installers and improves the overall USB creation flow, so you no longer need to restart the app after completion (or an error).

### ADDED
- Support for installer images in `.iso` and `.cdr` formats.
- New supported installers:
  - Mac OS X 10.4 Tiger (Single DVD and Multi DVD editions).
  - Mac OS X 10.5 Leopard.
  - Mac OS X 10.6 Snow Leopard.
- PowerPC booting instructions link added to the summary screen (shown for Tiger and Leopard installers).

### IMPROVED
- The app now automatically transitions to the summary screen when the USB creation process finishes.
- You can return to the start screen after an error or a successful run (from the summary screen), eliminating the need to restart the application.

### FIXED
- The app now correctly detects terminal error status, preventing the "Success" message from appearing when the process fails.

---

## v1.0.3

This release adds support for macOS Sierra 10.12.6 installers and includes minor visual refinements.

### ADDED
- Support for macOS Sierra installer (version 10.12.6 only).

### IMPROVED
- Minor visual interface adjustments.

---

## v1.0.2

This release extends source support with `.app` installers and fixes localization output in terminal workflow paths.

### ADDED
- Support for installers in `.app` format.

### FIXED
- Corrected terminal output localization for OS X Lion and Mountain Lion.

---

## v1.0.1

This release introduces Intel (`x86_64`) compatibility and fixes Tahoe installer support.

### ADDED
- `x86_64` support.

### FIXED
- Fixed support for macOS 26 Tahoe installer.

---

## v1.0

Initial public release of macUSB.

### INITIAL RELEASE
