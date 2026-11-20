#!/usr/bin/env bash
# ==============================================================================
# Module 05: ASUS Battery Health Charging Limit (80%)
# Prolongs lithium-ion battery lifespan by capping max charge level
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
err()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

BAT_NODE="/sys/class/power_supply/BAT0/charge_control_end_threshold"

install_battery_care() {
    info "Configuring Battery Health Charging limit..."

    if [[ ! -f "$BAT_NODE" ]]; then
        warn "Battery threshold node $BAT_NODE not found on this system. Installing service anyway..."
    fi

    install -m 644 "$ROOT_DIR/assets/services/asus-battery-care.service" /etc/systemd/system/asus-battery-care.service
    systemctl daemon-reload
    systemctl enable --now asus-battery-care.service

    if [[ -f "$BAT_NODE" ]]; then
        echo 80 > "$BAT_NODE" 2>/dev/null || true
        ok "Battery charge threshold capped at 80%."
    fi

    ok "Battery care service enabled."
}

uninstall_battery_care() {
    systemctl disable --now asus-battery-care.service 2>/dev/null || true
    rm -f /etc/systemd/system/asus-battery-care.service
    if [[ -f "$BAT_NODE" ]]; then
        echo 100 > "$BAT_NODE" 2>/dev/null || true
    fi
    ok "Battery care service removed (reset to 100%)."
}

action="${1:-install}"
case "$action" in
    install)   install_battery_care ;;
    uninstall) uninstall_battery_care ;;
    *) echo "Usage: $0 {install|uninstall}" >&2; exit 1 ;;
esac
