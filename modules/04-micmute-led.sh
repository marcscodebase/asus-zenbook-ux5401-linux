#!/usr/bin/env bash
# ==============================================================================
# Module 04: Microphone Mute LED Indicator Sync
# Synchronizes the LED on F9 with system microphone mute state
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
err()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

install_micmute_led() {
    info "Configuring ASUS platform::micmute LED trigger..."
    
    install -m 644 "$ROOT_DIR/assets/udev/99-asus-micmute.rules" /etc/udev/rules.d/99-asus-micmute.rules
    install -m 644 "$ROOT_DIR/assets/services/asus-micmute-led.service" /etc/systemd/system/asus-micmute-led.service

    systemctl daemon-reload
    systemctl enable --now asus-micmute-led.service
    udevadm control --reload-rules && udevadm trigger 2>/dev/null || true

    # Immediately set trigger if node exists
    local TRIGGER_NODE="/sys/devices/platform/asus-nb-wmi/leds/platform::micmute/trigger"
    if [[ -f "$TRIGGER_NODE" ]]; then
        echo "audio-micmute" > "$TRIGGER_NODE" 2>/dev/null || true
    fi

    ok "Microphone mute LED trigger configured."
}

uninstall_micmute_led() {
    systemctl disable --now asus-micmute-led.service 2>/dev/null || true
    rm -f /etc/systemd/system/asus-micmute-led.service
    rm -f /etc/udev/rules.d/99-asus-micmute.rules
    udevadm control --reload-rules || true
    ok "Microphone mute LED configuration removed."
}

action="${1:-install}"
case "$action" in
    install)   install_micmute_led ;;
    uninstall) uninstall_micmute_led ;;
    *) echo "Usage: $0 {install|uninstall}" >&2; exit 1 ;;
esac
