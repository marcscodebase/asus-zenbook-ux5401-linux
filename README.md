# ASUS Zenbook UX5401 Linux Fixes

[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-Supported-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org)
[![CachyOS](https://img.shields.io/badge/CachyOS-Supported-00A389)](https://cachyos.org)
[![Rust](https://img.shields.io/badge/Rust-Camera%20Daemon-DEA584?logo=rust&logoColor=white)](https://www.rust-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Hardware enablement scripts and daemon for the **ASUS Zenbook 14X OLED (`UX5401` / `UX5401ZA`)** on **Arch Linux** and **CachyOS** (GNOME).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/marcscodebase/asus-zenbook-ux5401-linux/main/install.sh -o install.sh && sudo bash install.sh --all && rm -f install.sh
```

Or from a local clone:

```bash
git clone https://github.com/marcscodebase/asus-zenbook-ux5401-linux.git
cd asus-zenbook-ux5401-linux
sudo ./install.sh --all
```

> Log out and back in (or reboot) once after installation so the `i2c`/`input`/`uinput` group memberships for the NumberPad take effect.

## Included Fixes

| Module | Hardware | Implementation |
| :--- | :--- | :--- |
| **Fingerprint** (`01-fingerprint.sh`) | Elan `04f3:0c6e` | Installs `fprintd` + `libfprint-elanpress-git` (AUR) and configures PAM for `sudo` and `polkit-1`. |
| **Camera E-Shutter** (`02-camera-shutter.sh`) | ACPI WMI `0x00060078` (<kbd>F10</kbd>) | Loads `acpi_call-dkms` and runs the Rust `asus-camera-shutter` daemon (`asus-camera-hotkey.service`) with desktop notifications. |
| **NumberPad 2.0** (`03-numberpad.sh`) | `ASUE140D` / `04F3:31B9` | Installs [`asus-numberpad-driver`](https://github.com/asus-linux-drivers/asus-numberpad-driver) (`v7.3.0`, `up5401ea` layout), udev rules (`hidraw`/`i2c`/`uinput`), and user systemd service. |
| **Mic Mute LED** (`04-micmute-led.sh`) | `platform::micmute` (<kbd>F9</kbd>) | Sets LED trigger to `audio-micmute` via udev rule and systemd oneshot service. |
| **Battery Care** (`05-battery-care.sh`) | `BAT0` charge threshold | Caps `charge_control_end_threshold` at `80%` on boot via systemd. |
| **Snipping Tool** (`--shortcuts`) | <kbd>F11</kbd> (`<Super><Shift>s`) | Maps `<Super><Shift>s` and `XF86SelectiveScreenshot` to GNOME's interactive screenshot UI (`show-screenshot-ui`). |

> **Note (<kbd>F8</kbd>):** <kbd>F8</kbd> is the external display switch (`Super+P` / `XF86Display`). GNOME handles it natively and only activates it when a second monitor is connected.

## Usage

```bash
# Interactive menu
sudo ./install.sh

# Individual modules
sudo ./install.sh --fingerprint
sudo ./install.sh --camera
sudo ./install.sh --numberpad
sudo ./install.sh --micmute
sudo ./install.sh --battery
sudo ./install.sh --shortcuts

# Camera shutter CLI
asus-camera-shutter [toggle|open|close|status]

# Uninstall everything
sudo ./uninstall.sh
```

## License

MIT — see [LICENSE](LICENSE). Maintained by **Marc Saier** ([@marcscodebase](https://github.com/marcscodebase)).
