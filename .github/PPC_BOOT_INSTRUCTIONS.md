# PPC USB BOOT - Open Firmware Instructions

This guide provides a step-by-step procedure to manually force a boot from a USB drive on PowerPC Apple computers (e.g., iMac G5, Power Mac G5) using Open Firmware.

## Prerequisites

* **OS Installer Image (User Provided):** A valid disk image of Mac OS X 10.4 Tiger or 10.5 Leopard.
* **USB Drive prepared by this application:** The app has automatically formatted the drive with the **Apple Partition Map** (APM) scheme and restored your image onto it.
* A wired USB keyboard.

## Procedure

1.  Insert the USB drive into a USB port on the computer.
2.  Power on the Mac and immediately press and hold: `Command (⌘)` + `Option (⌥)` + `O` + `F`.
3.  Release the keys when you see the white screen with the Open Firmware prompt.

### Step 1: Locate the USB Device

You need to find which alias points to your USB drive.

1.  Type `dev usb0` and press **Enter**.
2.  Type `ls` and press **Enter** to see the list of devices.
3.  Look for a disk entry, usually named `disk@1` (or `disk@2`, etc.).
    * **If you do not see a disk entry:** Repeat the steps above for other ports by typing `dev usb1`, `dev usb2`, etc., followed by `ls`, until you find the port with the disk.

### Step 2: Get the Hardware Path

1.  Select the disk by typing `dev disk@X` (replace `X` with the number found in the previous step, e.g., `dev disk@1`) and press **Enter**.
2.  Type `pwd` and press **Enter**.
3.  The screen will display the full hardware path to the device. **Write this path down exactly as it appears.**

### Step 3: The Boot Command

Construct the boot command using the path you found and the loader location. The OS X loader (`BootX`) is typically on partition 3.

**Syntax:**
`boot [path_from_step_2]:3,\System\Library\CoreServices\BootX`

---

### Example (iMac G5)

On an iMac G5, the hardware path is often complex and starts with `/ht@`. You must type the full path returned by the `pwd` command.

**Scenario:**
* You found the disk on `usb0` or `usb1`.
* The `pwd` command returned: `/ht@0,f2000000/pci@2/usb@b/disk@1`

**Command to type:**

```bash
boot /ht@0,f2000000/pci@2/usb@b/disk@1:3,\System\Library\CoreServices\BootX
