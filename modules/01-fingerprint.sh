#!/usr/bin/env bash
# ==============================================================================
# Module 01: Fingerprint Sensor Enablement
# Targets: Elan Microelectronics 04f3:0c6e press-sensor
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
err()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

install_fingerprint() {
    info "Checking for ELAN fingerprint sensor (04f3:0c6e)..."
    if ! lsusb | grep -qi "04f3:0c6e"; then
        warn "Device 04f3:0c6e was not detected via lsusb. Continuing anyway..."
    else
        ok "Detected ELAN fingerprint sensor (04f3:0c6e)."
    fi

    # Ensure fprintd is installed
    if ! pacman -Qs "^fprintd$" >/dev/null; then
        info "Installing fprintd..."
        pacman -S --noconfirm --needed fprintd
    fi

    # Check if patched libfprint-elanpress-git is installed
    if ! pacman -Qs "^libfprint-elanpress-git$" >/dev/null; then
        info "Installing libfprint-elanpress-git from AUR..."
        if command -v paru >/dev/null 2>&1; then
            # Run paru as original calling user if root
            local TARGET_USER="${SUDO_USER:-$USER}"
            sudo -u "$TARGET_USER" paru -S --noconfirm --needed libfprint-elanpress-git
        elif command -v yay >/dev/null 2>&1; then
            local TARGET_USER="${SUDO_USER:-$USER}"
            sudo -u "$TARGET_USER" yay -S --noconfirm --needed libfprint-elanpress-git
        else
            info "No AUR helper found. Building libfprint-elanpress-git with makepkg..."
            local BUILD_DIR="/tmp/libfprint-elanpress-git-build"
            rm -rf "$BUILD_DIR"
            local TARGET_USER="${SUDO_USER:-$USER}"
            sudo -u "$TARGET_USER" git clone https://aur.archlinux.org/libfprint-elanpress-git.git "$BUILD_DIR"
            (cd "$BUILD_DIR" && sudo -u "$TARGET_USER" makepkg -si --noconfirm)
            rm -rf "$BUILD_DIR"
        fi
        ok "libfprint-elanpress-git installed."
    else
        ok "libfprint-elanpress-git is already installed."
    fi

    # Configure PAM for sudo
    if ! grep -q "pam_fprintd.so" /etc/pam.d/sudo; then
        info "Adding pam_fprintd.so to /etc/pam.d/sudo..."
        sed -i '1a auth sufficient pam_fprintd.so' /etc/pam.d/sudo
        ok "/etc/pam.d/sudo configured."
    else
        ok "/etc/pam.d/sudo already contains pam_fprintd.so."
    fi

    # Configure PAM for polkit
    info "Installing /etc/pam.d/polkit-1 for GUI authorizations..."
    install -m 644 "$ROOT_DIR/assets/pam/polkit-1" /etc/pam.d/polkit-1
    ok "/etc/pam.d/polkit-1 configured."

    # Restart fprintd daemon
    info "Restarting fprintd service..."
    systemctl restart fprintd || true
    ok "Fingerprint module setup complete."
    echo -e "\e[36mTip: Run 'fprintd-enroll' to enroll your fingerprint if not done yet.\e[0m"
}

uninstall_fingerprint() {
    info "Reverting fingerprint PAM configurations..."
    sed -i '/pam_fprintd.so/d' /etc/pam.d/sudo 2>/dev/null || true
    rm -f /etc/pam.d/polkit-1
    ok "PAM configurations reverted."
}

action="${1:-install}"
case "$action" in
    install)   install_fingerprint ;;
    uninstall) uninstall_fingerprint ;;
    *) echo "Usage: $0 {install|uninstall}" >&2; exit 1 ;;
esac
