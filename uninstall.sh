#!/usr/bin/env bash
# ==============================================================================
# ASUS Zenbook UX5401 Uninstaller
# Reverts all applied hardware fixes and services.
# ==============================================================================

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }

info "Uninstalling all ASUS Zenbook hardware enablement modules..."

for mod in 01-fingerprint.sh 02-camera-shutter.sh 03-numberpad.sh 04-micmute-led.sh 05-battery-care.sh; do
    if [[ -f "$MODULES_DIR/$mod" ]]; then
        bash "$MODULES_DIR/$mod" uninstall || true
    fi
done

TARGET_USER="${SUDO_USER:-$USER}"
if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
    TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")
    RUNTIME_DIR="/run/user/$TARGET_UID"
    if [[ -S "$RUNTIME_DIR/bus" ]] && command -v gsettings >/dev/null 2>&1; then
        info "Resetting GNOME screenshot keybinding to default..."
        sudo -u "$TARGET_USER" \
            XDG_RUNTIME_DIR="$RUNTIME_DIR" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
            gsettings reset org.gnome.shell.keybindings show-screenshot-ui 2>/dev/null || true
    fi
fi

ok "Uninstallation complete. All configurations reverted."
