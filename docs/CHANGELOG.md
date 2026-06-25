# macUSB Release Changelog

---

## v2.3

macUSB v2.3 expands the Windows 10 and Windows 11 installer creation process with new autounattend-based configuration options, allowing prepared USB media to automate selected setup steps and bypass specific installation requirements. This release also adds SHA-256 checksum calculation for recognized disk images.

### ADDED: WINDOWS
Added automated Windows 10 and Windows 11 installer configuration options (#72) to:
- Bypass hardware requirement checks, including TPM 2.0, Secure Boot, and a minimum of 4 GB RAM (Windows 11 only).
- Automatically synchronize language and region settings with the host macOS system.
- Bypass the mandatory Microsoft Account sign-in requirement.
- Bypass the Wi-Fi network connection requirement during initial setup.
- Disable automatic BitLocker partition encryption on the target volume.
- Provision a predefined local user account automatically.
- Automatically decline diagnostic telemetry and privacy-tracking prompts.

### ADDED: OTHER
- Added SHA-256 checksum calculation for successfully recognized `.iso`, `.cdr`, and `.dmg` source images.
- Added the capability to write Linux-based `.img` images via **Tools → Write Raw Linux Image (.img)…** (#69).

### FIXED
- Fixed a localization issue across certain language packs that caused "Linux" branding to erroneously appear during Windows installer creation stages.

---

## v2.2

macUSB v2.2 adds support for recognizing Windows and Linux `.iso` files and for creating bootable USB media for both systems.

### ADDED: LINUX
- Added Linux `.iso` recognition with detected distribution name, version, architecture, and distro icon preview in analysis.
- Added ARM architecture labeling for recognized Linux sources.
- Added a dedicated process for creating bootable Linux USB media, using a `dd` write path with post-write SHA-256 verification.

### ADDED: WINDOWS
- Added Windows installer `.iso` recognition for sources from Windows XP and Windows Server 2003 onward, including version and architecture detection.
- Added ARM architecture labeling for recognized Windows sources.
- Added a dedicated process for creating bootable Windows USB media (supported for Windows 8 and newer, and Windows Server 2012 and newer), including MBR + FAT32 target formatting, automatic `.wim` splitting into `.swm` parts via `wimlib`, and write verification.
- Added conditional checks for `wimlib` when the selected Windows installer requires splitting the `.wim` file.

### ADDED: OTHER
- Added USB eject action on the summary screen.
- Added basic Touch Bar support showing app branding elements.

### IMPROVEMENTS
- Improved handling of USB devices that macOS cannot mount; when a macOS source is recognized, analysis now clearly informs the user and guides them to use Disk Utility.
- Added an automatic 20-second analysis timeout with a clear unrecognized-system status when detection cannot identify the selected source.
- The app window no longer recenters automatically on launch.
- Analysis now shows the selected source file name instead of the full file path.
- Minor UI polish across the flow.

---

## v2.1.1

This update improves installer reliability for legacy macOS installers and refreshes selected interface copy.

### FIXED
- Improved the installer `.app` build path for macOS Yosemite, El Capitan, and Sierra to prevent package-signature issues that could appear during installation.

### IMPROVEMENTS
- Improved Italian translation quality (#48).
- Updated the app tagline shown on the start screen.

---

## v2.1

macUSB v2.1 brings a new built-in macOS Downloader, improved helper reliability with automatic post-update repair, and a polished USB creation experience.

### NEW: DOWNLOADER
- Added a downloader module available from **Tools → Download macOS installer...** and from the analysis screen via **Download**.
- Added Apple-catalog installer discovery with grouped system families and an option to show all available versions.
- Added a complete staged workflow: connection, file download, verification, installer build, and final cleanup.
- Added installer verification based on package signature checks and data-integrity validation, applied according to system version and available verification methods.
- Added support for preparing installers across modern and legacy Apple distribution paths, including Sierra and older official Apple Support downloads.
- Added a completion summary with transfer metrics, destination details, and direct **Show in Finder** action.
- Added one-click handoff from downloader summary to analysis, allowing immediate use of the downloaded installer in USB creation.

### IMPROVEMENTS
- Helper repair is now more reliable and repeatable, especially in cases where macOS temporarily blocks or delays background activation, with more stable recovery after reconnection attempts.
- Helper repair is now presented as a system alert, improving UI consistency and making recovery status easier to follow.
- After updating to a new app version, helper auto-repair now runs automatically to ensure compatibility with newly introduced functionality.
- Added sleep prevention while downloading macOS and while creating a USB installer.
- Minor UI polish during the USB creation stage.

---

## v2.0.2

This patch release improves installer workflow reliability by tightening USB target validation rules and strengthening recovery behavior in helper and source-analysis edge cases.

### CHANGES
- USB minimum-capacity validation is now dynamic and tied to detected installer generation: Sonoma and older require 16 GB, Sequoia and newer require 32 GB.
- Selecting an APFS USB target now blocks proceeding to the next step and clearly guides the user to manually reformat the drive in Disk Utility before continuing.

### IMPROVEMENTS
- Improved helper repair with clearer diagnostics and more reliable recovery when macOS blocks background helper activation.
- When a selected `.cdr` or `.iso` source image is already mounted in macOS, analysis now shows a clear system alert and instructs the user to unmount the image before retrying.

---

## v2.0.1

This patch release focuses on resolving installer creation failures by enforcing the required **Full Disk Access** permission for macUSB before critical workflows continue.

### FIXED
- Improved startup permission flow to clearly require **Full Disk Access** when it is missing, reducing cases where installer creation could fail due to insufficient system permissions.
- Added a direct shortcut in **Tools → Grant Full Disk Access...** to quickly open System Settings and grant the required permission.
- Added a warning on the operation summary screen when required permissions are missing (Full Disk Access and/or helper background permission), so the risk is visible before starting the process.

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
