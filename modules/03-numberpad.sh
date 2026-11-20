#!/usr/bin/env bash
# ==============================================================================
# Module 03: ASUS NumberPad 2.0 (Touchpad Numpad) Driver
# Supports ASUE140D / ASUS touchpad with integrated numeric keypad
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
err()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

install_numberpad() {
    info "Checking for ASUS Touchpad with NumberPad..."
    if ! grep -qi "ASUE" /proc/bus/input/devices; then
        warn "ASUE touchpad device not detected in /proc/bus/input/devices. Continuing anyway..."
    else
        ok "Detected ASUS Touchpad device."
    fi

    info "Ensuring i2c-dev module is loaded..."
    echo "i2c-dev" > /etc/modules-load.d/i2c-dev.conf
    modprobe i2c-dev 2>/dev/null || true
    ok "i2c-dev module configured."

    # Install dependencies
    pacman -S --noconfirm --needed i2c-tools python python-libevdev 2>/dev/null || \
    pacman -S --noconfirm --needed i2c-tools python

    info "Installing asus-numberpad-driver..."
    local TARGET_USER="${SUDO_USER:-$USER}"

    if pacman -Qs "asus-touchpad-numpad-driver" >/dev/null; then
        ok "asus-touchpad-numpad-driver is already installed."
    elif command -v paru >/dev/null 2>&1; then
        sudo -u "$TARGET_USER" paru -S --noconfirm --needed asus-touchpad-numpad-driver || true
    elif command -v yay >/dev/null 2>&1; then
        sudo -u "$TARGET_USER" yay -S --noconfirm --needed asus-touchpad-numpad-driver || true
    fi

    # Fallback git installer if AUR was skipped or unavailable
    if ! systemctl list-unit-files | grep -qi "asus_touchpad_numpad"; then
        info "Setting up driver from asus-linux-drivers repository..."
        local CLONE_DIR="/tmp/asus-numberpad-driver"
        rm -rf "$CLONE_DIR"
        sudo -u "$TARGET_USER" git clone https://github.com/asus-linux-drivers/asus-numberpad-driver.git "$CLONE_DIR"
        (cd "$CLONE_DIR" && ./install.sh --auto || true)
        rm -rf "$CLONE_DIR"
    fi

    systemctl daemon-reload
    systemctl enable --now asus_touchpad_numpad.service 2>/dev/null || true
    ok "ASUS NumberPad driver setup finished."
    echo -e "\e[36mTip: Tap and hold the top-right corner of the touchpad to toggle the numeric keypad!\e[0m"
}

uninstall_numberpad() {
    info "Disabling asus_touchpad_numpad service..."
    systemctl disable --now asus_touchpad_numpad.service 2>/dev/null || true
    rm -f /etc/modules-load.d/i2c-dev.conf
    ok "NumberPad driver disabled."
}

action="${1:-install}"
case "$action" in
    install)   install_numberpad ;;
    uninstall) uninstall_numberpad ;;
    *) echo "Usage: $0 {install|uninstall}" >&2; exit 1 ;;
esac
