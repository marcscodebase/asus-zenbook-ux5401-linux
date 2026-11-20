use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const ACPI_CALL_PATH: &str = "/proc/acpi/call";
const STATE_FILE_PATH: &str = "/var/run/asus-camera-shutter.state";

const CMD_CLOSE: &str = "\\_SB.ATKD.WMNB 0x00 0x53564544 0x0000000000060078";
const CMD_OPEN: &str = "\\_SB.ATKD.WMNB 0x00 0x53564544 0x0000000100060078";
const CMD_STATUS: &str = "\\_SB.ATKD.WMNB 0x00 0x53545344 0x00060078";

const EV_KEY: u16 = 1;
const KEY_CAMERA: u16 = 212;
const KEY_SELECTIVE_SCREENSHOT: u16 = 634; // 0x27a (F11 Snipping Tool)
const INPUT_EVENT_SIZE: usize = 24; // 64-bit Linux input_event size

fn ensure_acpi_call() -> io::Result<()> {
    if !Path::new(ACPI_CALL_PATH).exists() {
        let _ = Command::new("modprobe").arg("acpi_call").status();
    }
    if !Path::new(ACPI_CALL_PATH).exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "Kernel module acpi_call is not loaded (/proc/acpi/call missing)",
        ));
    }
    Ok(())
}

fn write_acpi(cmd: &str) -> io::Result<()> {
    ensure_acpi_call()?;
    let mut file = OpenOptions::new().write(true).open(ACPI_CALL_PATH)?;
    file.write_all(cmd.as_bytes())?;
    Ok(())
}

fn send_desktop_notification(state: &str) {
    let (msg, icon) = if state == "closed" {
        ("Kamera geschützt (Blende geschlossen)", "camera-disabled")
    } else {
        ("Kamera aktiv (Blende geöffnet)", "camera-web")
    };

    // Broadcast notification to all active GUI user sessions
    if let Ok(entries) = fs::read_dir("/run/user") {
        for entry in entries.flatten() {
            if let Ok(file_name) = entry.file_name().into_string() {
                if let Ok(uid) = file_name.parse::<u32>() {
                    let bus_path = format!("/run/user/{}/bus", uid);
                    if Path::new(&bus_path).exists() {
                        let _ = Command::new("notify-send")
                            .env("DBUS_SESSION_BUS_ADDRESS", format!("unix:path={}", bus_path))
                            .args([
                                "-a",
                                "ASUS Hardware",
                                "-i",
                                icon,
                                "-h",
                                "string:x-canonical-private-synchronous:asus-camera",
                                "Kamera-Blende",
                                msg,
                            ])
                            .status();
                    }
                }
            }
        }
    }
}

pub fn get_status() -> String {
    if let Ok(state) = fs::read_to_string(STATE_FILE_PATH) {
        let s = state.trim();
        if s == "closed" || s == "open" {
            return s.to_string();
        }
    }

    if write_acpi(CMD_STATUS).is_ok() {
        if let Ok(mut file) = File::open(ACPI_CALL_PATH) {
            let mut buf = String::new();
            if file.read_to_string(&mut buf).is_ok() {
                let trimmed = buf.trim_matches('\0').trim();
                if trimmed == "0x0" {
                    return "closed".to_string();
                } else if trimmed == "0x1" {
                    return "open".to_string();
                }
            }
        }
    }
    "open".to_string()
}

pub fn shutter_open() -> io::Result<()> {
    write_acpi(CMD_OPEN)?;
    let _ = fs::write(STATE_FILE_PATH, "open\n");
    send_desktop_notification("open");
    println!("Camera shutter opened.");
    Ok(())
}

pub fn shutter_close() -> io::Result<()> {
    write_acpi(CMD_CLOSE)?;
    let _ = fs::write(STATE_FILE_PATH, "closed\n");
    send_desktop_notification("closed");
    println!("Camera shutter closed.");
    Ok(())
}

pub fn shutter_toggle() -> io::Result<()> {
    let current = get_status();
    if current == "closed" {
        shutter_open()
    } else {
        shutter_close()
    }
}

fn trigger_screenshot() {
    println!("F11 Snipping Tool key pressed! Notifying GNOME session...");
    if let Ok(entries) = fs::read_dir("/run/user") {
        for entry in entries.flatten() {
            if let Ok(file_name) = entry.file_name().into_string() {
                if let Ok(uid) = file_name.parse::<u32>() {
                    let bus_path = format!("/run/user/{}/bus", uid);
                    if Path::new(&bus_path).exists() {
                        let _ = Command::new("gsettings")
                            .env("DBUS_SESSION_BUS_ADDRESS", format!("unix:path={}", bus_path))
                            .args([
                                "set",
                                "org.gnome.shell.keybindings",
                                "show-screenshot-ui",
                                "['Print', 'XF86SelectiveScreenshot']",
                            ])
                            .status();
                    }
                }
            }
        }
    }
}

fn find_hotkey_device() -> Option<PathBuf> {
    let by_path = PathBuf::from("/dev/input/by-path/platform-asus-nb-wmi-event");
    if by_path.exists() {
        return Some(by_path);
    }

    if let Ok(content) = fs::read_to_string("/proc/bus/input/devices") {
        for section in content.split("\n\n") {
            if section.contains("Asus WMI hotkeys") {
                for line in section.lines() {
                    if line.starts_with("H: Handlers=") {
                        for token in line.split_whitespace() {
                            if token.starts_with("event") {
                                let dev = PathBuf::from(format!("/dev/input/{}", token));
                                if dev.exists() {
                                    return Some(dev);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    None
}

pub fn run_daemon(running: Arc<AtomicBool>) {
    println!("Starting ASUS Camera Hotkey Daemon (Rust)...");

    while running.load(Ordering::SeqCst) {
        let dev_path = match find_hotkey_device() {
            Some(path) => path,
            None => {
                thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        println!("Listening on device: {}", dev_path.display());
        let mut file = match File::open(&dev_path) {
            Ok(f) => f,
            Err(e) => {
                eprintln!("Failed to open {}: {}. Retrying...", dev_path.display(), e);
                thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        let mut buf = [0u8; INPUT_EVENT_SIZE];

        while running.load(Ordering::SeqCst) {
            match file.read_exact(&mut buf) {
                Ok(_) => {
                    // struct input_event in 64-bit Linux:
                    // sec: 8 bytes, usec: 8 bytes, type: 2 bytes, code: 2 bytes, value: 4 bytes
                    let ev_type = u16::from_ne_bytes([buf[16], buf[17]]);
                    let ev_code = u16::from_ne_bytes([buf[18], buf[19]]);
                    let ev_value = i32::from_ne_bytes([buf[20], buf[21], buf[22], buf[23]]);

                    if ev_type == EV_KEY && ev_value == 1 {
                        if ev_code == KEY_CAMERA {
                            println!("F10 Camera hotkey pressed! Toggling shutter...");
                            if let Err(e) = shutter_toggle() {
                                eprintln!("Error toggling camera shutter: {}", e);
                            }
                        } else if ev_code == KEY_SELECTIVE_SCREENSHOT {
                            trigger_screenshot();
                        }
                    }
                }
                Err(ref e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => {
                    if running.load(Ordering::SeqCst) {
                        eprintln!("Read error: {}. Reconnecting...", e);
                        thread::sleep(Duration::from_secs(2));
                    }
                    break;
                }
            }
        }
    }
    println!("ASUS Camera Hotkey Daemon stopped.");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let action = if args.len() > 1 {
        args[1].as_str()
    } else {
        "toggle"
    };

    match action {
        "open" => {
            if let Err(e) = shutter_open() {
                eprintln!("Error: {}", e);
                std::process::exit(1);
            }
        }
        "close" => {
            if let Err(e) = shutter_close() {
                eprintln!("Error: {}", e);
                std::process::exit(1);
            }
        }
        "toggle" => {
            if let Err(e) = shutter_toggle() {
                eprintln!("Error: {}", e);
                std::process::exit(1);
            }
        }
        "status" => {
            println!("{}", get_status());
        }
        "daemon" | "--daemon" => {
            let running = Arc::new(AtomicBool::new(true));
            run_daemon(running);
        }
        "--help" | "-h" => {
            println!("Usage: asus-camera-shutter [toggle|open|close|status|daemon]");
            println!("  toggle   Toggle physical camera shutter (default)");
            println!("  open     Open physical camera shutter");
            println!("  close    Close physical camera shutter");
            println!("  status   Show current shutter status");
            println!("  daemon   Run background F10 hotkey event listener");
        }
        unknown => {
            eprintln!("Unknown command: {}", unknown);
            eprintln!("Usage: asus-camera-shutter [toggle|open|close|status|daemon]");
            std::process::exit(1);
        }
    }
}
