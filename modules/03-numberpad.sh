#!/usr/bin/env bash
# ==============================================================================
# Module 03: ASUS NumberPad 2.0 (Touchpad Numpad) Driver
# Uses actively maintained asus-linux-drivers/asus-numberpad-driver (v7.3.0)
# Configured for Zenbook UX5401 / UX5401ZA (ASUE140D / 04F3:31B9, layout up5401ea)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DRIVER_REPO="https://github.com/asus-linux-drivers/asus-numberpad-driver.git"
DRIVER_TAG="v7.3.0"
DRIVER_DIR="/usr/share/asus-numberpad-driver"
LAYOUT_NAME="up5401ea"

info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()    { echo -e "\e[32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
err()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

get_target_user() {
    local u="${SUDO_USER:-$USER}"
    if [[ "$u" == "root" ]]; then
        u=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)
    fi
    echo "$u"
}

cleanup_legacy_driver() {
    # Remove broken legacy mohamed-badaoui/asus-touchpad-numpad-driver if installed
    if systemctl list-unit-files asus_touchpad_numpad.service >/dev/null 2>&1; then
        info "Removing legacy asus_touchpad_numpad.service..."
        systemctl disable --now asus_touchpad_numpad.service 2>/dev/null || true
    fi
    rm -f /etc/systemd/system/asus_touchpad_numpad.service
    rm -rf /usr/share/asus_touchpad_numpad-driver
    systemctl daemon-reload
}

install_numberpad() {
    local TARGET_USER
    TARGET_USER="$(get_target_user)"
    if [[ -z "$TARGET_USER" ]]; then
        err "Could not determine non-root desktop user for NumberPad user service."
        exit 1
    fi

    local TARGET_UID TARGET_HOME TARGET_RUNTIME_DIR TARGET_DBUS
    TARGET_UID="$(id -u "$TARGET_USER")"
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    TARGET_RUNTIME_DIR="/run/user/$TARGET_UID"
    TARGET_DBUS="unix:path=$TARGET_RUNTIME_DIR/bus"

    cleanup_legacy_driver

    info "Checking for ASUS Touchpad with NumberPad..."
    if ! grep -qiE "ASUE|ASUF|ELAN" /proc/bus/input/devices; then
        warn "ASUS touchpad device not detected in /proc/bus/input/devices. Continuing anyway..."
    else
        ok "Detected ASUS Touchpad device."
    fi

    info "Configuring i2c-dev and uinput kernel modules..."
    cat << 'EOF' > /etc/modules-load.d/asus-numberpad.conf
i2c-dev
uinput
EOF
    rm -f /etc/modules-load.d/i2c-dev.conf
    modprobe i2c-dev 2>/dev/null || true
    modprobe uinput 2>/dev/null || true
    ok "Kernel modules i2c-dev and uinput configured."

    info "Installing driver system dependencies..."
    pacman -S --noconfirm --needed \
        ibus libevdev curl i2c-tools python python-virtualenv python-systemd \
        libxml2 libxkbcommon gcc pkgconf libxcb wayland xorg-xinput git

    info "Configuring system groups and udev rules for $TARGET_USER..."
    local grp
    for grp in input i2c uinput numberpad; do
        getent group "$grp" >/dev/null 2>&1 || groupadd --system "$grp"
    done

    local GROUPS_BEFORE
    GROUPS_BEFORE="$(id -nG "$TARGET_USER")"
    usermod -aG i2c,input,uinput,numberpad "$TARGET_USER"

    cat << 'EOF' > /etc/udev/rules.d/99-asus-numberpad-uinput.rules
SUBSYSTEM=="misc", KERNEL=="uinput", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="uinput", MODE="0660"
EOF

    cat << 'EOF' > /etc/udev/rules.d/99-asus-numberpad-i2c-dev.rules
ACTION!="remove", KERNEL=="i2c-[0-9]*", SUBSYSTEM=="i2c-dev", TAG+="uaccess", GROUP="i2c", MODE="0660"
EOF

    # Prefer hidraw feature reports (ordered before 73-seat-late.rules for uaccess)
    local TOUCHPAD_PHYS
    TOUCHPAD_PHYS="$(grep -A5 -i touchpad /proc/bus/input/devices | grep -o 'Phys=i2c-[^[:space:]]*' | cut -d= -f2 | sort -u | head -n1 || true)"
    if [[ -n "$TOUCHPAD_PHYS" ]]; then
        cat << EOF > /etc/udev/rules.d/70-asus-numberpad-hidraw.rules
ACTION!="remove", SUBSYSTEM=="hidraw", KERNELS=="$TOUCHPAD_PHYS", TAG+="uaccess", GROUP="i2c", MODE="0660"
EOF
        ok "Configured hidraw udev rule for $TOUCHPAD_PHYS."
    else
        warn "Touchpad I2C Phys path not detected; falling back to i2c-dev udev rule."
    fi

    udevadm control --reload-rules
    udevadm trigger --sysname-match=uinput 2>/dev/null || true
    udevadm trigger --attr-match=subsystem=i2c-dev 2>/dev/null || true
    udevadm trigger --subsystem-match=hidraw 2>/dev/null || true
    ok "Groups and udev rules applied."

    info "Fetching asus-linux-drivers/asus-numberpad-driver ($DRIVER_TAG)..."
    local CLONE_DIR="/tmp/asus-numberpad-driver-repo"
    rm -rf "$CLONE_DIR"
    git clone --depth 1 --branch "$DRIVER_TAG" "$DRIVER_REPO" "$CLONE_DIR"

    mkdir -p "$DRIVER_DIR/layouts"
    install -Dm755 "$CLONE_DIR/numberpad.py" "$DRIVER_DIR/numberpad.py"
    install -Dm644 "$CLONE_DIR"/layouts/*.py -t "$DRIVER_DIR/layouts"
    install -Dm644 "$CLONE_DIR"/requirements*.txt -t "$DRIVER_DIR"
    rm -rf "$CLONE_DIR"
    chown -R "$TARGET_USER:" "$DRIVER_DIR"

    # Detect session type (default Wayland on GNOME/CachyOS)
    local SESSION_TYPE="wayland"
    if [[ -n "${XDG_SESSION_TYPE:-}" && "${XDG_SESSION_TYPE}" == "x11" ]]; then
        SESSION_TYPE="x11"
    elif [[ -d "$TARGET_RUNTIME_DIR" ]] && ! ls "$TARGET_RUNTIME_DIR"/wayland-* >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
        SESSION_TYPE="x11"
    fi

    info "Setting up Python virtual environment for $TARGET_USER ($SESSION_TYPE)..."
    sudo -Hu "$TARGET_USER" virtualenv --python=/usr/bin/python3 --system-site-packages "$DRIVER_DIR/.env"
    sudo -Hu "$TARGET_USER" "$DRIVER_DIR/.env/bin/pip" install --quiet --upgrade pip setuptools
    sudo -Hu "$TARGET_USER" "$DRIVER_DIR/.env/bin/pip" install --quiet \
        -r "$DRIVER_DIR/requirements.txt" \
        -r "$DRIVER_DIR/requirements.systemd.txt"

    if [[ "$SESSION_TYPE" == "x11" ]]; then
        sudo -Hu "$TARGET_USER" "$DRIVER_DIR/.env/bin/pip" install --quiet -r "$DRIVER_DIR/requirements.x11.txt"
    else
        sudo -Hu "$TARGET_USER" "$DRIVER_DIR/.env/bin/pip" install --quiet -r "$DRIVER_DIR/requirements.wayland.txt"
    fi
    ok "Python environment and dependencies installed."

    info "Installing systemd user service for $TARGET_USER (layout: $LAYOUT_NAME)..."
    local USER_SYSTEMD_DIR="$TARGET_HOME/.config/systemd/user"
    sudo -Hu "$TARGET_USER" mkdir -p "$USER_SYSTEMD_DIR"

    cat << EOF > "$USER_SYSTEMD_DIR/asus_numberpad_driver@.service"
[Unit]
Description=ASUS NumberPad 2.0 Driver
After=graphical-session.target
StartLimitBurst=20
StartLimitIntervalSec=300

[Service]
Type=simple
ExecStart=$DRIVER_DIR/.env/bin/python3 $DRIVER_DIR/numberpad.py $LAYOUT_NAME $DRIVER_DIR/
TimeoutSec=5
Restart=on-failure
RestartSec=2
StandardOutput=null
StandardError=null
PassEnvironment=DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS
Environment="XDG_SESSION_TYPE=$SESSION_TYPE"
Environment="PATH=/usr/sbin:/usr/bin:/bin"

[Install]
WantedBy=graphical-session.target default.target
EOF
    chown "$TARGET_USER:" "$USER_SYSTEMD_DIR/asus_numberpad_driver@.service"

    if [[ -S "$TARGET_RUNTIME_DIR/bus" ]]; then
        sudo -Hu "$TARGET_USER" \
            XDG_RUNTIME_DIR="$TARGET_RUNTIME_DIR" \
            DBUS_SESSION_BUS_ADDRESS="$TARGET_DBUS" \
            systemctl --user daemon-reload
        sudo -Hu "$TARGET_USER" \
            XDG_RUNTIME_DIR="$TARGET_RUNTIME_DIR" \
            DBUS_SESSION_BUS_ADDRESS="$TARGET_DBUS" \
            systemctl --user enable "asus_numberpad_driver@${TARGET_USER}.service" || true
        sudo -Hu "$TARGET_USER" \
            XDG_RUNTIME_DIR="$TARGET_RUNTIME_DIR" \
            DBUS_SESSION_BUS_ADDRESS="$TARGET_DBUS" \
            systemctl --user restart "asus_numberpad_driver@${TARGET_USER}.service" || true
        ok "ASUS NumberPad user service enabled and running."
    else
        warn "No active user D-Bus session found. Enable after login with:"
        warn "  systemctl --user enable --now asus_numberpad_driver@${TARGET_USER}.service"
    fi

    if ! echo " $GROUPS_BEFORE " | grep -q " input " || ! echo " $GROUPS_BEFORE " | grep -q " uinput "; then
        warn "User '$TARGET_USER' was newly added to the i2c/input/uinput groups."
        warn "Please log out and back in (or reboot) once for NumberPad permissions to take effect!"
    fi

    echo -e "\e[36mTip: Hold/tap the top-right corner of the touchpad to toggle the NumberPad, and top-left for brightness/calculator.\e[0m"
}

uninstall_numberpad() {
    local TARGET_USER
    TARGET_USER="$(get_target_user)"

    cleanup_legacy_driver

    if [[ -n "$TARGET_USER" ]]; then
        local TARGET_UID TARGET_HOME TARGET_RUNTIME_DIR TARGET_DBUS
        TARGET_UID="$(id -u "$TARGET_USER")"
        TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
        TARGET_RUNTIME_DIR="/run/user/$TARGET_UID"
        TARGET_DBUS="unix:path=$TARGET_RUNTIME_DIR/bus"

        info "Disabling asus_numberpad_driver user service for $TARGET_USER..."
        if [[ -S "$TARGET_RUNTIME_DIR/bus" ]]; then
            sudo -u "$TARGET_USER" \
                XDG_RUNTIME_DIR="$TARGET_RUNTIME_DIR" \
                DBUS_SESSION_BUS_ADDRESS="$TARGET_DBUS" \
                systemctl --user disable --now "asus_numberpad_driver@${TARGET_USER}.service" 2>/dev/null || true
            sudo -u "$TARGET_USER" \
                XDG_RUNTIME_DIR="$TARGET_RUNTIME_DIR" \
                DBUS_SESSION_BUS_ADDRESS="$TARGET_DBUS" \
                systemctl --user daemon-reload 2>/dev/null || true
        fi
        rm -f "$TARGET_HOME/.config/systemd/user/asus_numberpad_driver@.service"
    fi

    rm -rf "$DRIVER_DIR"
    rm -f /etc/modules-load.d/asus-numberpad.conf /etc/modules-load.d/i2c-dev.conf
    rm -f /etc/udev/rules.d/99-asus-numberpad-uinput.rules \
          /etc/udev/rules.d/99-asus-numberpad-i2c-dev.rules \
          /etc/udev/rules.d/70-asus-numberpad-hidraw.rules
    udevadm control --reload-rules 2>/dev/null || true
    ok "NumberPad driver uninstalled."
}

action="${1:-install}"
case "$action" in
    install)   install_numberpad ;;
    uninstall) uninstall_numberpad ;;
    *) echo "Usage: $0 {install|uninstall}" >&2; exit 1 ;;
esac
