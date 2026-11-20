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

ok "Uninstallation complete. All configurations reverted."
