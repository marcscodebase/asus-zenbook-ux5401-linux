#!/usr/bin/env bash
# ==============================================================================
# ASUS Zenbook UX5401 / UX5401ZA Linux Hardware Enablement Master Installer
# Target: Arch Linux / CachyOS
# Supports both local repository execution and standalone curl execution.
# ==============================================================================

set -euo pipefail

# Ensure script is executed as root
if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/marcscodebase/asus-zenbook-ux5401-linux.git"
TEMP_CLONE=""

# Cleanup handler for standalone execution
cleanup() {
    if [[ -n "$TEMP_CLONE" && -d "$TEMP_CLONE" ]]; then
        rm -rf "$TEMP_CLONE"
    fi
}
trap cleanup EXIT

# If executed standalone (e.g. via curl), fetch full repo into temp dir
if [[ ! -d "$SCRIPT_DIR/modules" ]]; then
    echo "Running in standalone mode. Fetching repository components..."
    TEMP_CLONE=$(mktemp -d /tmp/asus-zenbook-ux5401-XXXXXX)
    git clone --depth 1 "$REPO_URL" "$TEMP_CLONE"
    SCRIPT_DIR="$TEMP_CLONE"
fi

MODULES_DIR="$SCRIPT_DIR/modules"

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
err()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

print_banner() {
    clear || true
    echo -e "\e[36m"
    echo "================================================================="
    echo "       ASUS Zenbook UX5401 Linux Hardware Enablement Suite       "
    echo "================================================================="
    echo -e "\e[0m"
    echo "Detected System: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo 'Unknown ASUS Laptop')"
    echo "Kernel:          $(uname -r)"
    echo "Target User:     ${SUDO_USER:-$USER}"
    echo "-----------------------------------------------------------------"
}

configure_desktop_shortcuts() {
    info "Configuring F11 Snipping Tool keybinding for GNOME..."
    local TARGET_USER="${SUDO_USER:-$USER}"
    if [[ -n "$TARGET_USER" ]]; then
        local TARGET_UID
        TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")
        if [[ -d "/run/user/$TARGET_UID" ]]; then
            sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
                gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print', 'XF86SelectiveScreenshot']" 2>/dev/null || true
            ok "F11 Snipping Tool keybinding configured."
        fi
    fi
}

run_module() {
    local mod="$1"
    local script="$MODULES_DIR/$mod"
    if [[ -x "$script" || -f "$script" ]]; then
        bash "$script" install
    else
        err "Module not found: $script"
    fi
}

install_all() {
    info "Installing all ASUS Zenbook hardware enablement modules..."
    echo ""
    run_module "01-fingerprint.sh"
    echo ""
    run_module "02-camera-shutter.sh"
    echo ""
    run_module "03-numberpad.sh"
    echo ""
    run_module "04-micmute-led.sh"
    echo ""
    run_module "05-battery-care.sh"
    echo ""
    configure_desktop_shortcuts
    echo ""
    ok "All ASUS Zenbook UX5401 fixes successfully applied!"
    echo -e "\e[32m"
    echo "================================================================="
    echo "                      Installation Complete!                     "
    echo "================================================================="
    echo -e "\e[0m"
    echo "✓ Fingerprint:   Sensor enabled for sudo, polkit, and login."
    echo "✓ E-Shutter:     F10 key toggles physical camera shield + OSD."
    echo "✓ Snipping Tool: F11 key opens interactive screenshot overlay."
    echo "✓ NumberPad:     Hold top-right corner of touchpad for 1s to toggle."
    echo "✓ Mic Mute:      F9 indicator LED synchronized."
    echo "✓ Battery:       Health charge threshold capped at 80%."
    echo ""
}

show_menu() {
    print_banner
    echo "Choose which features to activate:"
    echo "  [1] Fingerprint Sensor (libfprint-elanpress-git + sudo/polkit PAM)"
    echo "  [2] Electronic Camera Shutter (acpi_call-dkms + F10 Hotkey Hook + OSD)"
    echo "  [3] ASUS NumberPad 2.0 (Touchpad numeric keypad driver - Automated)"
    echo "  [4] Microphone Mute LED Sync (F9 indicator trigger)"
    echo "  [5] Battery Health Charging (80% charge threshold)"
    echo "  [A] Activate ALL features (Recommended)"
    echo "  [Q] Quit"
    echo ""
    read -rp "Enter selection [A]: " choice
    choice="${choice:-A}"

    case "${choice,,}" in
        1) run_module "01-fingerprint.sh" ;;
        2) run_module "02-camera-shutter.sh" ;;
        3) run_module "03-numberpad.sh" ;;
        4) run_module "04-micmute-led.sh" ;;
        5) run_module "05-battery-care.sh" ;;
        a|all) install_all ;;
        q|quit) echo "Aborted."; exit 0 ;;
        *) err "Invalid option: $choice"; exit 1 ;;
    esac
}

# Command-line options
if [[ $# -gt 0 ]]; then
    case "$1" in
        --all|-a)
            print_banner
            install_all
            ;;
        --fingerprint)
            run_module "01-fingerprint.sh"
            ;;
        --camera)
            run_module "02-camera-shutter.sh"
            ;;
        --numberpad)
            run_module "03-numberpad.sh"
            ;;
        --micmute)
            run_module "04-micmute-led.sh"
            ;;
        --battery)
            run_module "05-battery-care.sh"
            ;;
        --help|-h)
            echo "Usage: sudo $0 [--all|--fingerprint|--camera|--numberpad|--micmute|--battery]"
            exit 0
            ;;
        *)
            err "Unknown option: $1"
            exit 1
            ;;
    esac
else
    show_menu
fi
