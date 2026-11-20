#!/usr/bin/env bash
# ==============================================================================
# Module 03: ASUS NumberPad 2.0 (Touchpad Numpad) Driver
# Supports ASUE140D / ASUS touchpad with integrated numeric keypad
# Fully automated installation (layout ux433fa, key 6) without prompts
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

    # Install required dependencies
    info "Installing driver dependencies..."
    pacman -S --noconfirm --needed i2c-tools python python-libevdev git

    info "Setting up ASUS NumberPad driver (automated for ux433fa / UX5401 layout)..."
    local DRIVER_DIR="/usr/share/asus_touchpad_numpad-driver"
    local CLONE_DIR="/tmp/asus-touchpad-numpad-driver-repo"

    rm -rf "$CLONE_DIR"
    git clone --depth 1 https://github.com/mohamed-badaoui/asus-touchpad-numpad-driver.git "$CLONE_DIR"

    mkdir -p "$DRIVER_DIR/numpad_layouts"
    install -Dm755 "$CLONE_DIR/asus_touchpad.py" "$DRIVER_DIR/asus_touchpad.py"
    install -Dm755 "$CLONE_DIR"/numpad_layouts/*.py -t "$DRIVER_DIR/numpad_layouts"
    rm -rf "$CLONE_DIR"

    # Install systemd service with fixed parameters for Zenbook 14 (ux433fa layout, key 6)
    cat << 'EOF' > /etc/systemd/system/asus_touchpad_numpad.service
[Unit]
Description=Asus Touchpad NumberPad Driver
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/share/asus_touchpad_numpad-driver/asus_touchpad.py ux433fa 6
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now asus_touchpad_numpad.service
    ok "ASUS NumberPad driver installed and service started."
    echo -e "\e[36mTip: Halte die obere rechte Ecke des Touchpads für ca. 1 Sekunde gedrückt, um das Numpad ein-/auszuschalten!\e[0m"
}

uninstall_numberpad() {
    info "Disabling asus_touchpad_numpad service..."
    systemctl disable --now asus_touchpad_numpad.service 2>/dev/null || true
    rm -f /etc/systemd/system/asus_touchpad_numpad.service
    rm -rf /usr/share/asus_touchpad_numpad-driver
    rm -f /etc/modules-load.d/i2c-dev.conf
    systemctl daemon-reload
    ok "NumberPad driver disabled."
}

action="${1:-install}"
case "$action" in
    install)   install_numberpad ;;
    uninstall) uninstall_numberpad ;;
    *) echo "Usage: $0 {install|uninstall}" >&2; exit 1 ;;
esac
