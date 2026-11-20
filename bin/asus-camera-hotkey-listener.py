#!/usr/bin/env python3
"""
ASUS Zenbook Camera Hotkey Listener
Monitors input events from 'Asus WMI hotkeys' for KEY_CAMERA (212)
and triggers /usr/local/bin/asus-camera-shutter toggle.
Zero external dependencies (uses standard library struct/os/select).
"""

import os
import re
import select
import signal
import struct
import subprocess
import sys
import time

EV_KEY = 1
KEY_CAMERA = 212
INPUT_EVENT_FORMAT = "qqHHi"
EVENT_SIZE = struct.calcsize(INPUT_EVENT_FORMAT)

running = True


def signal_handler(signum, frame):
    global running
    running = False


def find_hotkey_device():
    # 1. Check symlink by-path
    by_path = "/dev/input/by-path/platform-asus-nb-wmi-event"
    if os.path.exists(by_path):
        return by_path

    # 2. Check /proc/bus/input/devices
    try:
        with open("/proc/bus/input/devices", "r") as f:
            content = f.read()

        sections = content.strip().split("\n\n")
        for section in sections:
            if "Asus WMI hotkeys" in section:
                match = re.search(r"Handlers=.*?(event\d+)", section)
                if match:
                    event_name = match.group(1)
                    dev_path = f"/dev/input/{event_name}"
                    if os.path.exists(dev_path):
                        return dev_path
    except Exception as e:
        sys.stderr.write(f"Error reading /proc/bus/input/devices: {e}\n")

    # 3. Fallback scan /sys/class/input
    try:
        for entry in os.listdir("/sys/class/input"):
            name_file = os.path.join("/sys/class/input", entry, "device", "name")
            if os.path.exists(name_file):
                with open(name_file, "r") as nf:
                    if "Asus WMI hotkeys" in nf.read():
                        dev_path = f"/dev/input/{entry}"
                        if os.path.exists(dev_path):
                            return dev_path
    except Exception:
        pass

    return None


def trigger_shutter():
    script = "/usr/local/bin/asus-camera-shutter"
    if not os.path.exists(script):
        script = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "asus-camera-shutter"
        )

    try:
        subprocess.run([script, "toggle"], check=True)
    except Exception as err:
        sys.stderr.write(f"Failed to execute camera shutter: {err}\n")


def main():
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print("Starting ASUS Camera Hotkey Listener...")
    sys.stdout.flush()

    while running:
        device_path = find_hotkey_device()
        if not device_path:
            time.sleep(2)
            continue

        try:
            print(f"Monitoring device: {device_path}")
            sys.stdout.flush()
            with open(device_path, "rb") as fd:
                poll = select.poll()
                poll.register(fd, select.POLLIN)

                while running:
                    events = poll.poll(1000)
                    if not events:
                        continue

                    data = fd.read(EVENT_SIZE)
                    if len(data) < EVENT_SIZE:
                        break

                    sec, usec, ev_type, ev_code, ev_value = struct.unpack(
                        INPUT_EVENT_FORMAT, data
                    )
                    # Trigger on key down (ev_value == 1) for KEY_CAMERA
                    if ev_type == EV_KEY and ev_code == KEY_CAMERA and ev_value == 1:
                        print("F10 / Camera hotkey pressed. Toggling shutter...")
                        sys.stdout.flush()
                        trigger_shutter()

        except Exception as e:
            if running:
                sys.stderr.write(f"Device read error: {e}. Reconnecting in 2s...\n")
                sys.stderr.flush()
                time.sleep(2)


if __name__ == "__main__":
    main()
