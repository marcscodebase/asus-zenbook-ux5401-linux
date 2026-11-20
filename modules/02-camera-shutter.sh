#!/usr/bin/env bash
# ==============================================================================
# Module 02: Electronic Camera Shutter (E-Shutter) Controller & Hotkey Hook
# Uses compiled Rust binary (prebuilt or compiled on the fly)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
err()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

install_camera_shutter() {
    info "Installing acpi_call kernel module..."
    if ! pacman -Qs "acpi_call" >/dev/null; then
        pacman -S --noconfirm --needed acpi_call
    fi

    # Ensure acpi_call loads on boot
    echo "acpi_call" > /etc/modules-load.d/acpi_call.conf
    modprobe acpi_call 2>/dev/null || true
    ok "Kernel module acpi_call configured and loaded."

    info "Deploying asus-camera-shutter binary..."
    local BIN_SRC="$ROOT_DIR/bin/asus-camera-shutter"

    # If cargo is available and source exists, we can optionally build from source
    if command -v cargo >/dev/null 2>&1 && [[ -f "$ROOT_DIR/Cargo.toml" && ! -f "$BIN_SRC" ]]; then
        info "Building asus-camera-shutter from Rust source..."
        (cd "$ROOT_DIR" && cargo build --release && cp target/release/asus-camera-shutter "$BIN_SRC")
    fi

    if [[ ! -f "$BIN_SRC" ]]; then
        err "Binary $BIN_SRC not found. Please compile via 'cargo build --release'."
        exit 1
    fi

    install -m 755 "$BIN_SRC" /usr/local/bin/asus-camera-shutter
    ok "asus-camera-shutter installed to /usr/local/bin."

    info "Installing sudoers rule for user-space triggers..."
    install -m 440 "$ROOT_DIR/assets/sudoers/asus-zenbook-fixes" /etc/sudoers.d/asus-zenbook-fixes
    ok "/etc/sudoers.d/asus-zenbook-fixes installed."

    info "Installing and starting asus-camera-hotkey service..."
    install -m 644 "$ROOT_DIR/assets/services/asus-camera-hotkey.service" /etc/systemd/system/asus-camera-hotkey.service
    systemctl daemon-reload
    systemctl enable --now asus-camera-hotkey.service
    ok "asus-camera-hotkey.service is enabled and running."

    echo -e "\e[36mTip: Press F10 to test your electronic camera privacy shutter!\e[0m"
}

uninstall_camera_shutter() {
    info "Stopping and disabling asus-camera-hotkey.service..."
    systemctl disable --now asus-camera-hotkey.service 2>/dev/null || true
    rm -f /etc/systemd/system/asus-camera-hotkey.service
    systemctl daemon-reload

    rm -f /usr/local/bin/asus-camera-shutter
    rm -f /etc/sudoers.d/asus-zenbook-fixes
    rm -f /etc/modules-load.d/acpi_call.conf
    ok "Camera shutter controller uninstalled."
}

action="${1:-install}"
case "$action" in
    install)   install_camera_shutter ;;
    uninstall) uninstall_camera_shutter ;;
    *) echo "Usage: $0 {install|uninstall}" >&2; exit 1 ;;
esac
