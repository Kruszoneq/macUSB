# 💾 macUSB

### Creating bootable macOS and OS X USB drives has never been easier!

![Platform](https://img.shields.io/badge/Platform-macOS-black) ![Architecture](https://img.shields.io/badge/Architecture-Apple_Silicon/Intel-black) ![License](https://img.shields.io/badge/License-MIT-blue) ![Vibe Coded](https://img.shields.io/badge/Vibe%20Coded%2C%20purple)


**macUSB** is a one-click tool that transforms your modern Mac (Apple Silicon) into a service machine capable of reviving older Apple computers.

---
## 📸 Screenshots

<p align="center">
  <img src="screenshots/WelcomeView.png" width="45%" alt="Welcome Screen">
  <img src="screenshots/SystemAnalysisView.png" width="45%" alt="System Analysis">
</p>
<p align="center">
  <img src="screenshots/UniversalInstallerView.png" width="45%" alt="Installation Process">
  <img src="screenshots/FinishUSBView.png" width="45%" alt="Process Finished">
</p>

## 🚀 About the Project

With Apple's transition to its own silicon (M1, M2, M3...), preparing installation media for older Intel-based computers has become a challenge. Many people encounter Terminal errors, issues with expired certificates in old installers, or simply a lack of compatibility with system tools.

**macUSB solves this problem.**

The application automates the entire process of creating a bootable USB drive. You don't need to search for commands online, worry about disk formatting, or manually fix validation errors in old installation files.

### What do you gain?
* **Legacy Support:** The ability to create installers for systems over a decade old (e.g., OS X Lion) directly on the latest Mac on Apple Silicon.
* **Time Saving:** The app detects the system version in the **`.dmg` or `.app`** file, formats the drive, and copies files automatically.
* **Auto Fixes:** For certain older systems (e.g., High Sierra/Mojave), the app automatically applies necessary fixes so the installer works despite expired Apple certificates.

> **Fun Fact:** The application was created using the "Vibe Coding" method in collaboration with the Gemini 3 Pro and GPT-5 AI models. The project proves that programming barriers (even cross-architectural ones) can be overcome with determination and AI support.

---

## ⚠️ Installation and First Run

The application is an open-source project and does not possess a paid Apple Developer signature, so Gatekeeper will block it by default.

**How to run the app for the first time:**

1. Try to open the app – you will see an "Unknown Developer" message.
2. Go to **System Settings** -> **Privacy & Security**.
3. Scroll down to the **Security** section and click the **"Open Anyway"** button next to macUSB.
4. When writing the system to the flash drive, a system prompt asking for **access to removable volumes** will appear. You must **Allow** this so the application can format and write the system to the USB.

---

## ⚙️ Requirements

### Host Computer (where you run the app):
* **Processor:** Both Apple Silicon (M1/M2/M3, etc.) and Intel are supported.
* **System:** **macOS Sonoma 14.6** or newer.
* **Storage:** Minimum of **15 GB** of free disk space is required **to create the installers**.

### USB Drives (for installer creation):
* **Capacity:** Minimum of **16 GB** is required.
* **Recommendation:** USB 3.0 or newer is highly recommended for faster installation times.

### Installation Files:
The program supports both **`.dmg`** disk images and raw **`.app`** installer files.

> **💡 Pro Tip:** The best way to obtain valid files is the free application **[MIST by ninxsoft](https://github.com/ninxsoft/Mist)**. Simply select the system version you are interested in. This guarantees the correct file structure/source.

---

## 💿 List of Tested Installers

The table below shows systems that have successfully passed tests for creating a bootable USB media using this application.
*(Status "YES" / ✅ means the app can correctly create a USB drive with this system).*

| System | Version | USB Creation Status |
| :--- | :--- | :---: |
| **macOS Tahoe** | 26 | ✅ |
| **macOS Sequoia** | 15 | ✅ |
| **macOS Sonoma** | 14 | ✅ |
| **macOS Ventura** | 13 | ✅ |
| **macOS Monterey** | 12 | ✅ |
| **macOS Big Sur** | 11 | ✅ |
| **macOS Catalina** | 10.15 | ✅ |
| **macOS Mojave** | 10.14 | ✅ |
| **macOS High Sierra** | 10.13 | ✅ |
| **macOS Sierra** | 10.12 | ❌ |
| **OS X El Capitan** | 10.11 | ✅ |
| **OS X Yosemite** | 10.10 | ✅ |
| **OS X Mavericks** | 10.9 | ❌ |
| **OS X Mountain Lion** | 10.8 | ✅ |
| **OS X Lion** | 10.7 | ✅ |

---

## 🐛 Known Issues and Limitations

During testing, compatibility issues were identified with certain system versions on Apple Silicon architecture. To ensure the stability of your computer and avoid critical errors, **the application intentionally blocks the selection of the following systems**:

* **macOS Sierra (10.12):** The USB creation process fails, causing a rapid RAM fill-up and severe system stuttering.
* **OS X Mavericks (10.9):** The installer file is incorrectly verified by the system as "damaged," preventing the procedure from starting.

If a **`.dmg`** image or a **`.app`** installer with one of the above systems is selected, macUSB will display an unsupported message and will not allow you to proceed to the next step.

---

## 🌍 Available Languages

The application interface automatically adapts to the system language:

* 🇵🇱 Polish (PL)
* 🇺🇸 English (EN)
* 🇩🇪 German (DE)
* 🇯🇵 Japanese (JA)
* 🇫🇷 French (FR)
* 🇪🇸 Spanish (ES)
* 🇧🇷 Portuguese (PT-BR)
* 🇨🇳 Simplified Chinese (ZH-Hans)
* 🇷🇺 Russian (RU)

---

## ⚖️ License

This project is licensed under the **MIT License**.

This means you are free to use, copy, modify, and distribute this code, provided you keep the author information. The software is provided "as is", without warranty of any kind.

Copyright © 2025 Kruszoneq

---

**Note:** The application interface and this README file were translated using Gemini 3 Pro. Please excuse any potential translation errors.
