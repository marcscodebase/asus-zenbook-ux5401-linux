# ASUS Zenbook UX5401 / UX5401ZA Linux Hardware Enablement

[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-Supported-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org)
[![CachyOS](https://img.shields.io/badge/CachyOS-Optimized-00A389)](https://cachyos.org)
[![Rust](https://img.shields.io/badge/Rust-Compiled%20Binary-DEA584?logo=rust&logoColor=white)](https://www.rust-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Complete hardware enablement suite and automated fixes for the **ASUS Zenbook 14X OLED (UX5401 / UX5401ZA / Space Edition)** on **Arch Linux** and **CachyOS**.

Out of the box, several proprietary ASUS hardware features are non-functional under Linux. This repository provides automated, modular fixes to bring full parity with Windows.

---

## 🚀 One-Liner Installation

Open your terminal and run the following command. It downloads the installer, sets up all hardware features, and cleans up after itself automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/marcscodebase/asus-zenbook-ux5401-linux/main/install.sh -o install.sh && sudo bash install.sh --all && rm -f install.sh
```

*(Or if you prefer cloning the repository)*:
```bash
git clone https://github.com/marcscodebase/asus-zenbook-ux5401-linux.git && cd asus-zenbook-ux5401-linux && sudo ./install.sh --all
```

---

## ⚡ Feature Support Matrix

| Feature | Hardware Identifier | Default Linux State | With This Suite |
| :--- | :--- | :---: | :---: |
| **Fingerprint Sensor** | Elan `04f3:0c6e` (Power button) | ❌ Broken (Stock driver fails) | ✅ **Working** (`sudo`, `polkit`, GDM login) |
| **E-Shutter (Camera Privacy Shield)** | ACPI WMI motor (`0x00060078`) | ❌ Inactive (F10 key dead) | ✅ **Working** (F10 key + Desktop OSD via Rust binary) |
| **F11 Snipping Tool** | Keyboard chord (`<Super><Shift>s`) | ❌ Types literal `S` | ✅ **Working** (Opens GNOME interactive screenshot UI) |
| **ASUS NumberPad 2.0** | Touchpad Numpad (`ASUE140D` / `04F3:31B9`) | ❌ Inactive | ✅ **Working** (`asus-numberpad-driver`, `up5401ea` layout) |
| **Microphone Mute LED** | `platform::micmute` (F9 key) | ❌ Out of sync | ✅ **Working** (Hardware LED synced with ALSA) |
| **Battery Health Care** | `charge_control_end_threshold` | ❌ 100% constant charging | ✅ **Working** (Capped at 80% to protect battery) |

> **Note on F8 (Display Mode / Project):** On the UX5401ZA, <kbd>F8</kbd> is the external display switcher (`Super+P` / `XF86Display`). GNOME handles this natively via `switch-monitor`, which only shows/cycles display modes when an external monitor is connected.

---

## 📦 What Each Module Does

### 1. Fingerprint Reader (`modules/01-fingerprint.sh`)
* Replaces the flawed upstream `libfprint` package with the community-patched `libfprint-elanpress-git` from the AUR, which correctly treats the `04f3:0c6e` reader as a touch/press sensor rather than a swipe sensor.
* Configures PAM `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1` so you can authorize terminal `sudo` commands and graphical root popups simply by touching the power button.

### 2. Electronic Camera Shutter (`modules/02-camera-shutter.sh` & `src/`)
* Written in **Rust**: Deploys a high-performance, compiled binary (`bin/asus-camera-shutter`) with zero runtime overhead (< 1 MB RAM).
* Integrates `acpi_call-dkms` kernel module to control the physical privacy motor via ASUS WMI calls (`\_SB.ATKD.WMNB`).
* Deploys a background daemon (`asus-camera-hotkey.service`) that captures the `KEY_CAMERA` hotkey press and drives the motor in real-time.
* Shows a native desktop on-screen notification (*"Kamera-Blende geschlossen / geöffnet"*).

### 3. ASUS NumberPad 2.0 (`modules/03-numberpad.sh`)
* Installs the actively maintained [`asus-linux-drivers/asus-numberpad-driver`](https://github.com/asus-linux-drivers/asus-numberpad-driver) (`v7.3.0`) configured automatically for the UX5401ZA (`ASUE140D` / `04F3:31B9`, `up5401ea` layout).
* Configures `i2c-dev`, `uinput`, `hidraw` udev rules, user groups, and a Wayland/X11 systemd user service (`asus_numberpad_driver@<user>.service`).
* Enables holding/tapping the top-right corner of the touchpad to toggle the illuminated numeric keypad, and the top-left corner for backlight brightness / calculator.

### 4. Microphone Mute LED (`modules/04-micmute-led.sh`)
* Sets up a udev rule and systemd trigger so that pressing <kbd>F9</kbd> toggles the physical LED indicator on the key in sync with PipeWire/WirePlumber mute state.

### 5. Battery Care (`modules/05-battery-care.sh`)
* Preserves lithium-ion battery health by capping the maximum charging threshold to 80% via `charge_control_end_threshold`.

### 6. Desktop Shortcuts (`install.sh --shortcuts`)
* Binds `<Super><Shift>s` (the hardware chord emitted by <kbd>F11</kbd> on UX5401ZA) alongside `Print` and `XF86SelectiveScreenshot` to GNOME's interactive screenshot overlay (`org.gnome.shell.keybindings show-screenshot-ui`).

---

## 🛠 Manual Usage & Options

You can also run the installer interactively or target specific modules:

```bash
# Interactive selection menu:
sudo ./install.sh

# Target specific modules:
sudo ./install.sh --fingerprint
sudo ./install.sh --camera
sudo ./install.sh --numberpad
sudo ./install.sh --micmute
sudo ./install.sh --battery
sudo ./install.sh --shortcuts
```

### Manual Camera Shutter CLI
The shutter controller can also be invoked directly from the terminal or bound to any custom shortcut:

```bash
# Toggle shutter:
asus-camera-shutter toggle

# Explicitly open or close:
asus-camera-shutter open
asus-camera-shutter close

# Check status:
asus-camera-shutter status
```

---

## 🔄 Uninstallation

To cleanly revert all modifications and remove services:

```bash
sudo ./uninstall.sh
```

---

## 👤 Author

* **Marc Saier** ([@marcscodebase](https://github.com/marcscodebase))
* Email: [marc@saier.io](mailto:marc@saier.io)

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
