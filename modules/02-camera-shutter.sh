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
    info "Installing acpi_call-dkms kernel module for running kernel..."
    if ! pacman -Qs "^acpi_call-dkms$" >/dev/null; then
        pacman -R --noconfirm acpi_call 2>/dev/null || true
        pacman -S --noconfirm --needed acpi_call-dkms
    fi

    # Ensure acpi_call loads on boot
    echo "acpi_call" > /etc/modules-load.d/acpi_call.conf
    modprobe acpi_call 2>/dev/null || true

    if [[ ! -e "/proc/acpi/call" ]]; then
        warn "/proc/acpi/call not active yet. Triggering DKMS build..."
        dkms autoinstall 2>/dev/null || true
        modprobe acpi_call 2>/dev/null || true
    fi

    ok "Kernel module acpi_call configured and loaded."

    info "Deploying asus-camera-shutter binary..."
    local BIN_SRC="$ROOT_DIR/bin/asus-camera-shutter"

    # If cargo is available and source exists, build release binary as calling user
    local TARGET_USER="${SUDO_USER:-$USER}"
    if command -v cargo >/dev/null 2>&1 && [[ -f "$ROOT_DIR/Cargo.toml" ]]; then
        info "Building latest asus-camera-shutter from Rust source..."
        if [[ "$TARGET_USER" != "root" && -w "$ROOT_DIR" ]]; then
            sudo -u "$TARGET_USER" bash -c "cd '$ROOT_DIR' && cargo build --release && strip target/release/asus-camera-shutter && cp target/release/asus-camera-shutter '$BIN_SRC'"
        else
            (cd "$ROOT_DIR" && cargo build --release && strip target/release/asus-camera-shutter && cp target/release/asus-camera-shutter "$BIN_SRC")
        fi
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
