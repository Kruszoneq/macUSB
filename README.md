# <img src="screenshots/macUSBiconPNG.png" alt="macUSB" width="64" height="64" style="vertical-align: middle;"> macUSB

### Creating bootable macOS and OS X USB drives has never been easier!

![Platform](https://img.shields.io/badge/Platform-macOS-black) ![Architecture](https://img.shields.io/badge/Architecture-Apple_Silicon/Intel-black) ![License](https://img.shields.io/badge/License-MIT-blue) [Security](https://img.shields.io/badge/Security-Notarized-success) ![Vibe Coded](https://img.shields.io/badge/Vibe%20Coded%20-gray) ![Vibe Coded](https://img.shields.io/badge/Vibe%20Coded%20-gray) [![Website](https://img.shields.io/badge/Website-macUSB-blueviolet)](https://kruszoneq.github.io/macUSB/)


**macUSB** is a one-click tool that transforms your modern Mac (Apple Silicon) into a service machine capable of reviving older Apple computers.

---
## 🖼️ Preview

<p align="center">
  <img src="screenshots/macUSBtheme.png" alt="macUSB – UI preview" width="980">
</p>

## 🚀 About the Project

With Apple's transition to its own silicon (M1, M2, M3...), preparing installation media for older Intel- and PowerPC-based computers has become a challenge. Many people encounter Terminal errors, issues with expired certificates in old installers, or simply a lack of compatibility with system tools.

**macUSB solves this problem.**

The application automates the entire process of creating a bootable USB drive. You don't need to search for commands online, worry about disk formatting, or manually fix validation errors in old installation files.

### What do you gain?
* **Legacy Support:** The ability to create installers for systems over a decade old (e.g., OS X Lion) directly on the latest Mac on Apple Silicon.
* **Time Saving:** The app detects the system version in the **`.dmg`**, **`.iso`**, **`.cdr`** or **`.app`** file, formats the drive, and copies files automatically.
* **Auto Fixes:** For certain systems (e.g., High Sierra/Mojave), the app automatically applies necessary fixes so the installer works despite expired Apple certificates.
* **PowerPC Revival:** The app formats USB drives to the Apple Partition Map (APM) scheme required by PowerPC Macs and transfers the installer directly from **`.iso`**, **`.cdr`** or **`.dmg`** files. This allows for installation without the need for physical CDs/DVDs or FireWire drives.
  
  > 📖 **Guide:** [Step-by-step: Booting from USB on PowerPC Macs using Open Firmware](https://kruszoneq.github.io/macUSB/pages/guides/ppc_boot_instructions.html)

* **Security:** Starting with version **v1.1.2**, the application is officially **notarized by Apple**. This guarantees that the software is free from malicious code and ensures a seamless, secure first launch on macOS without requiring any extra security workarounds.

---

**Fun Fact:** The application was created using the "Vibe Coding" method. Every single function has been rigorously verified for correct operation to ensure full stability. This project proves that programming barriers (even cross-architectural ones) can be overcome with determination and AI support while maintaining the highest standards of code quality.

---

## ⚙️ Requirements

### Host Computer (where you run the app):
* **Processor:** Both Apple Silicon and Intel are supported.
* **System:** **macOS Sonoma 14.6** or newer.
* **Storage:** Minimum of **15 GB** of free disk space is required **to create the installers**.

### USB Drives & External Storage
* **Capacity:** A minimum of **16 GB** is required.
* **Speed:** USB 3.0 or newer is highly recommended for faster installation times.
* **External Drives (HDD/SSD):** By default, only USB flash drives are detected for safety. To use external disks, enable **Options** → **Enable external drives support**.

### Installation Files:
The program supports **`.dmg`**, **`.cdr`** and **`.iso`** disk images, as well as raw **`.app`** installer files.

> **Pro Tip:** Where to get valid files?
> * **OS X 10.7 - 10.8** and **10.10 – macOS 26:** The most convenient solution is downloading via the free app **[Mist](https://github.com/ninxsoft/Mist)**.
> * **OS X 10.9:** The recommended source is **[Mavericks Forever](https://mavericksforever.com/)** (macUSB support was developed based on the image from this site).
> * **Mac OS X 10.4 – 10.6 (Intel):** Disk images are available on the **Internet Archive**.
> * **Mac OS X 10.4 – 10.5 (PowerPC):** Images for PPC architecture can be found on **Macintosh Garden**.

---

## 💿 Supported Versions

The table lists systems supported by the application that are successfully recognized and written to a USB drive.

| System | Version | Supported |
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
| **macOS Sierra**[^1] | 10.12 | ✅ |
| **OS X El Capitan** | 10.11 | ✅ |
| **OS X Yosemite** | 10.10 | ✅ |
| **OS X Mavericks**[^2] | 10.9 | ✅ |
| **OS X Mountain Lion** | 10.8 | ✅ |
| **OS X Lion** | 10.7 | ✅ |
| **Mac OS X Snow Leopard** | 10.6 | ✅ |
| **Mac OS X Leopard** | 10.5 | ✅ |
| **Mac OS X Tiger**[^3] | 10.4 | ✅ |

[^1]: Only version **10.12.6** is supported.
[^2]: Fully works with the image downloaded from [Mavericks Forever](https://mavericksforever.com/). Images from other sources have not been verified and may cause errors.
[^3]: The **Single DVD** edition is recognized automatically. Instructions for the **Multi-DVD** edition are available on the application's website: [Tiger Multi-DVD Guide](https://kruszoneq.github.io/macUSB/pages/guides/multidvd_tiger.html).

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

## 🛠️ Support & Bug Reports

If you encounter any issues, please report them via [GitHub Issues](https://github.com/Kruszoneq/macUSB/issues). To help me replicate and fix the bug faster, please include the following details:

* **Description of the issue:** What happened and at what stage?
* **Screenshot:** An image of the error or the application window is highly helpful for diagnosis.
* **Host OS Version:** Which macOS version are you running macUSB on (e.g., macOS Sequoia 15.1)?
* **Target OS Version:** Which system are you trying to prepare (e.g., Mac OS X Tiger 10.4)?
* **Installer Source & LINK:** Where did the installer file come from (e.g., Mist, Internet Archive)? **If possible, please provide a link to the source** – this allows me to download the exact same image and test it on my end.

---

## ⚖️ License

This project is licensed under the **MIT License**.

This means you are free to use, copy, modify, and distribute this code, provided you keep the author information. The software is provided "as is", without warranty of any kind.

Copyright © 2025-2026 Krystian Pierz

---

**Note:** The application interface and this README file were translated using Gemini 3 Pro. Please excuse any potential translation errors.

