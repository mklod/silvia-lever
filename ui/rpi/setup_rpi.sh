#!/bin/bash
# Last modified: 2026-04-24--0148
# One-time setup for Raspberry Pi deployment.
# Tested target: RPi 4/5 with 1080p touchscreen, Raspberry Pi OS (Bookworm).
#
# Boot-time history (RPi 4B, Samsung EVO Plus 64GB SD):
#   26.3 s  baseline (untouched Pi OS Bookworm)
#   16.1 s  after disabling NM-wait-online + cloud-init + cups + bluetooth + ModemManager
#   15.0 s  after additional avahi/rpcbind/udisks2/e2scrub_reap + Plymouth mask + visual quiet
#   11.7 s  after swapping NetworkManager → systemd-networkd + wpa_supplicant@wlan0
#   10.6 s  L1: lightdm out, getty autologin → labwc-pi → silvia (XDG autostart)
#          End state. multi-user.target ≈ 7.1 s userspace.
#
# L2 (cage kiosk) was tried — same boot time as L1 but broke touch input
# (cage doesn't auto-rotate the touchscreen calibration matrix), showed a
# persistent mouse cursor, and added two visible black-terminal flashes.
# labwc-pi via kanshi handles all of these for free, so we kept L1.
# See KIOSK.md for the full L1/L2/L3/L4 discussion.
#
# Things that were tried and DID NOT help (to save future time chasing them):
#   - `fastboot` in cmdline:        no-op, fsck was already skipped on clean fs
#   - `dtoverlay=disable-bt`:       no measurable boot-time delta (BT module isn't slow)
#   - IPv6 disable in NM:           no measurable boot-time delta (WPA handshake ≠ DAD)
#   - Empty Before=/After= in NM drop-in: systemd ignores the reset for ordering deps
#   - Direct edit of NM unit file (remove Before=network.target): made boot WORSE because
#     multi-user.target.wants/ holds a direct edge to NM, so NM ran as a singleton (slower)
#   - Override systemd-user-sessions to drop network.target After= dep: also ineffective
#
# To break the 15 s wall, the genuine remaining options are:
#   - A2-rated SD card (drop-in hardware): -1.5-2.5 s
#   - systemd-networkd swap (config rewrite, see notes below): -3-4 s
#   - USB-SSD boot (hardware): -3-5 s
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Defensive: pscp -r from Windows strips +x. Make our launchers executable
# regardless of how the tree got here (git preserves +x; pscp doesn't).
chmod +x "$SCRIPT_DIR"/*.sh "$PROJECT_DIR/ui/source/run_silvia.py" 2>/dev/null || true

echo "==> Installing system packages..."
sudo apt-get update
# labwc + kanshi + wlr-randr are NOT installed by default on Pi OS Lite
# (they ship with the labwc-pi metapackage on Pi OS Full / Bookworm desktop).
# Install them explicitly so this script works on Lite images too.
sudo apt-get install -y \
    labwc \
    kanshi \
    wlr-randr \
    seatd \
    python3 \
    python3-pyqt6 \
    python3-pyqt6.qtquick \
    python3-pyqt6.qtqml \
    python3-pyqt6.sip \
    python3-serial \
    qt6-wayland \
    libxcb-cursor0 \
    libqt6svg6 \
    qt6-svg-plugins \
    librsvg2-common \
    qml6-module-qtqml \
    qml6-module-qtquick \
    qml6-module-qtquick-window \
    qml6-module-qtquick-controls \
    qml6-module-qtquick-layouts \
    qml6-module-qtquick-shapes \
    qml6-module-qtquick-templates \
    qml6-module-qtquick-effects \
    qml6-module-qtquick-nativestyle

echo "==> Registering gdk-pixbuf SVG loader (for .desktop icon rendering)..."
if [ -x /usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders ]; then
    sudo /usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders --update-cache
fi

echo "==> Adding user '$USER' to dialout group (for /dev/ttyACM*)..."
sudo usermod -aG dialout "$USER"

echo "==> Installing Teensy udev rule (ignore ModemManager, dialout access)..."
sudo install -m 0644 "$SCRIPT_DIR/99-teensy.rules" /etc/udev/rules.d/99-teensy.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=tty

echo "==> Configuring pcmanfm for touch-friendly launching..."
# single_click=1: tap opens instead of selects (rename-prone on touchscreens)
# quick_exec=1: execute .desktop directly instead of prompting Execute/Terminal dialog
LIBFM_CONF="$HOME/.config/libfm/libfm.conf"
mkdir -p "$(dirname "$LIBFM_CONF")"
if [ ! -f "$LIBFM_CONF" ]; then
    printf '[config]\nsingle_click=1\nquick_exec=1\n' > "$LIBFM_CONF"
else
    # Ensure [config] exists
    grep -q '^\[config\]' "$LIBFM_CONF" || printf '\n[config]\n' >> "$LIBFM_CONF"
    # Upsert each key
    for kv in "single_click=1" "quick_exec=1"; do
        key="${kv%%=*}"
        if grep -q "^${key}=" "$LIBFM_CONF"; then
            sed -i "s|^${key}=.*|${kv}|" "$LIBFM_CONF"
        else
            sed -i "/^\[config\]/a ${kv}" "$LIBFM_CONF"
        fi
    done
fi
# Respawn pcmanfm desktop so new config takes effect
pkill -f "pcmanfm --desktop" 2>/dev/null || true

echo "==> Installing desktop shortcut..."
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="$DESKTOP_DIR/silvia.desktop"
sed "s|@PROJECT_DIR@|$PROJECT_DIR|g" "$SCRIPT_DIR/silvia.desktop.in" > "$DESKTOP_FILE"
chmod +x "$DESKTOP_FILE"

echo "==> Trimming boot-time services (espresso machine doesn't need them)..."
# Baseline Pi OS boot is ~26 s; these cuts get it to ~10-13 s. All reversible
# with `sudo systemctl enable --now <name>` (or `unmask` for the masked ones).
# Idempotent — re-running this script just re-disables what's already disabled.
sudo systemctl disable --now \
    NetworkManager-wait-online \
    cups cups-browsed cups.socket cups.path \
    bluetooth \
    ModemManager \
    rpi-eeprom-update \
    rpi-resize-swap-file \
    avahi-daemon avahi-daemon.socket \
    rpcbind rpcbind.socket \
    e2scrub_reap \
    udisks2 \
    2>/dev/null || true
# cloud-init: headless cloud-image provisioning, adds ~13 s. Useless here.
sudo systemctl mask \
    cloud-init cloud-init-local cloud-init-main cloud-init-network \
    cloud-config cloud-final \
    2>/dev/null || true
# Plymouth: USE a custom all-black theme to cover the kernel→userspace
# tty text flashes. We previously masked all plymouth-*, but ~2 terminal
# flashes between firmware and labwc were visible. A black splash in
# initramfs closes that window at a cost of ~0.5 s of boot.
#
# NOTE: plymouth-quit.service MUST remain enabled — plymouth-quit-wait
# holds multi-user.target until plymouth quits, and if plymouth-quit is
# masked the whole boot chain hangs (getty@tty1 is Before=plymouth-quit).
sudo systemctl unmask \
    plymouth-start.service plymouth-quit.service \
    plymouth-quit-wait.service plymouth-read-write.service \
    2>/dev/null || true
sudo apt-get install -y plymouth plymouth-themes 2>&1 | tail -2
sudo mkdir -p /usr/share/plymouth/themes/black
sudo tee /usr/share/plymouth/themes/black/black.plymouth > /dev/null <<'EOF'
[Plymouth Theme]
Name=Black
Description=Solid black - no logo, no animation
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/black
ScriptFile=/usr/share/plymouth/themes/black/black.script
EOF
sudo tee /usr/share/plymouth/themes/black/black.script > /dev/null <<'EOF'
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);
EOF
sudo plymouth-set-default-theme -R black 2>&1 | tail -3

echo "==> Quietening boot visuals (rainbow / RPi splash / kernel text / cursor)..."
# config.txt: disable the firmware rainbow boot screen + Bluetooth (saves ~0.5 s
# of BT firmware load + module init; we use WiFi for the LAN link).
if grep -q "^#disable_splash=1" /boot/firmware/config.txt; then
    sudo sed -i "s|^#disable_splash=1|disable_splash=1|" /boot/firmware/config.txt
elif ! grep -q "^disable_splash=1" /boot/firmware/config.txt; then
    echo "disable_splash=1" | sudo tee -a /boot/firmware/config.txt > /dev/null
fi
if ! grep -q "^dtoverlay=disable-bt" /boot/firmware/config.txt; then
    echo "dtoverlay=disable-bt" | sudo tee -a /boot/firmware/config.txt > /dev/null
fi
# cmdline.txt: append kernel-quiet + fastboot flags if not already present.
# fastboot skips the unconditional fsck on every boot (still runs when fs flags
# say it's needed). Saves ~0.5 s.
CMDLINE=/boot/firmware/cmdline.txt
# quiet+splash+plymouth.ignore-serial-consoles are present in Pi OS Full's
# default cmdline but NOT in Pi OS Lite. Without `splash` plymouth-start
# runs but draws nothing — kernel + systemd messages flood the visible tty.
# Belt-and-suspenders: ensure all the flags are present regardless of base image.
for flag in "loglevel=3" "vt.global_cursor_default=0" "logo.nologo" "fastboot" \
            "quiet" "splash" "plymouth.ignore-serial-consoles"; do
    if ! grep -q "$flag" "$CMDLINE"; then
        sudo sed -i "s|\$| $flag|" "$CMDLINE"
    fi
done
# Move kernel/systemd/getty console output off tty1 → tty3 (invisible). tty1
# is the VT labwc takes over; any text spam there flashes through as the VT
# handoff happens. Moving it to tty3 makes tty1 stay black until labwc draws.
if grep -q "console=tty1" "$CMDLINE"; then
    sudo sed -i 's/console=tty1/console=tty3/' "$CMDLINE"
fi

echo "==> Disabling IPv6 on NetworkManager connections (saves ~1-2 s of DAD wait)..."
# Only the active wired + wlan profiles; loopback rejects the change.
for conn in $(sudo nmcli -t -f NAME,TYPE c show | grep -vE "^[^:]+:loopback$" | cut -d: -f1); do
    sudo nmcli c modify "$conn" ipv6.method disabled 2>/dev/null && \
        echo "    $conn -> ipv6 disabled" || true
done

echo "==> Installing silvia-deadman (auto-rollback timer for risky changes)..."
sudo install -m 0755 "$SCRIPT_DIR/silvia-deadman" /usr/local/bin/silvia-deadman

echo "==> Network manager: prefer systemd-networkd over NM (saves ~3 s of boot)..."
# Write the networkd config (DHCP fallback if no static lease — change Address=
# below if your router doesn't reserve the IP). The wpa_supplicant credentials
# file is intentionally NOT created here — it carries the WiFi PSK and would
# expose secrets if committed. Restore it from a snapshot or write by hand
# (template at the end of this section).
sudo apt-get install -y wpasupplicant 2>&1 | tail -2
if [ ! -f /etc/systemd/network/25-wlan0.network ]; then
    sudo tee /etc/systemd/network/25-wlan0.network > /dev/null <<'NWEOF'
[Match]
Name=wlan0

[Network]
DHCP=ipv4
NWEOF
    echo "    wrote /etc/systemd/network/25-wlan0.network (DHCP)"
fi

# Cutover only if (a) wpa_supplicant credentials exist, AND (b) NM is still
# the active manager. Otherwise leave network alone — fresh install path is:
# create /etc/wpa_supplicant/wpa_supplicant-wlan0.conf manually, then re-run
# this script.
if [ -f /etc/wpa_supplicant/wpa_supplicant-wlan0.conf ] && \
   systemctl is-enabled --quiet NetworkManager.service 2>/dev/null; then
    echo "    swapping NetworkManager → systemd-networkd + wpa_supplicant@wlan0"
    sudo systemctl disable NetworkManager.service NetworkManager-dispatcher.service 2>/dev/null || true
    sudo systemctl enable systemd-networkd.service "wpa_supplicant@wlan0.service" 2>/dev/null || true
    echo "    (reboot required for cutover to take effect)"
elif [ ! -f /etc/wpa_supplicant/wpa_supplicant-wlan0.conf ]; then
    echo "    SKIP networkd cutover: no /etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
    echo "    To enable: create that file with content like:"
    echo "      ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev"
    echo "      update_config=1"
    echo "      country=US"
    echo "      network={ ssid=\"<your-ssid>\" psk=\"<your-psk>\" key_mgmt=WPA-PSK }"
    echo "    chmod 0600 it, then re-run this script."
else
    echo "    networkd already active or NM already disabled — no cutover needed"
fi

echo "==> Wiring tty1 autologin → labwc-pi → silvia (L1 path)..."
# getty autologin override. Two things are needed together to beat the boot
# race where pam_nologin would otherwise reject the autologin:
#   1. After=systemd-user-sessions.service — orders getty after user-sessions.
#   2. Type=idle — holds agetty until the system "settles" (no other units
#      starting), giving pam a few extra ms past the user-sessions handshake.
# Without Type=idle, agetty still occasionally races ahead and hangs at the
# login prompt ('(agetty)' state) instead of autologging.
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null <<EOF
[Unit]
After=systemd-user-sessions.service

[Service]
Type=idle
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear --noissue --nohostname %I \$TERM
TTYVTDisallocate=no
EOF
# --noissue / --nohostname strip the "Debian GNU/Linux tty1" banner that
# would otherwise flash on tty1 before bash_profile exec's labwc-pi.
# TTYVTDisallocate=no keeps the VT alive across the getty→labwc handoff
# (prevents a brief VT-reset flash).
# .hushlogin silences pam_motd + last-login printed during autologin.
touch "$HOME/.hushlogin"
sudo systemctl daemon-reload

# bash_profile launches labwc directly with --config-dir, NOT labwc-pi.
# labwc-pi would read /etc/xdg/labwc/autostart (pcmanfm-pi + wf-panel-pi +
# lxsession-xdg-autostart) even if a user autostart also existed — both would
# run in parallel, drawing the desktop/panel briefly and spawning duplicate
# silvia instances. --config-dir pins labwc to our user config only.
# We inherit the Pi env from /usr/bin/setup_env (labwc-pi sourced it too).
#
# NOTE: no 'exec' on labwc. If labwc returns immediately (no HDMI attached,
# e.g. when this card is being prepared as a spare), bash falls through to
# an interactive shell instead of exiting and triggering a getty restart
# loop until systemd hits the start-rate-limit. With display attached,
# labwc never returns until shutdown.
cat > "$HOME/.bash_profile" <<EOF
# Kiosk launcher: tty1 autologin → labwc (user config) → silvia.
if [ -z "\$WAYLAND_DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    . /usr/bin/setup_env 2>/dev/null || true
    export XDG_SESSION_TYPE=wayland XDG_SESSION_DESKTOP=labwc XDG_CURRENT_DESKTOP=labwc:wlroots
    /usr/bin/labwc --config-dir "\$HOME/.config/labwc" -m
fi
[ -f ~/.profile ] && . ~/.profile
EOF

# Minimal user-level labwc autostart. With --config-dir above, this is the
# ONLY autostart labwc reads. Kanshi provides 90° rotation from
# ~/.config/kanshi/config. Touchscreen → output mapping lives in labwc
# rc.xml.
mkdir -p "$HOME/.config/labwc"
cat > "$HOME/.config/labwc/autostart" <<EOF
#!/bin/sh
/usr/bin/kanshi &
$SCRIPT_DIR/run_silvia.sh &
EOF
chmod +x "$HOME/.config/labwc/autostart"

# Kanshi config — drives the 90° portrait rotation for the HDMI panel.
# labwc-pi (on Pi OS Full) creates an empty kanshi config and the rotation
# comes from somewhere else; on Pi OS Lite we use plain labwc and need to
# write this file ourselves or the panel renders landscape.
mkdir -p "$HOME/.config/kanshi"
cat > "$HOME/.config/kanshi/config" <<'EOF'
profile {
    output HDMI-A-1 enable scale 1.000000 mode 1080x1920@59.719 position 0,0 transform 90
}
EOF

# labwc rc.xml — touch → output mapping. Without this, touch coordinates
# stay in raw (un-rotated) space while the display is rotated 90° via
# kanshi → touch appears mirrored/rotated. mapToOutput tells labwc to apply
# the output's transform to the touch device. Pi OS Full ships this via
# labwc-pi's default config; Pi OS Lite needs it written explicitly.
install -m 0644 "$SCRIPT_DIR/labwc-rc.xml" "$HOME/.config/labwc/rc.xml"

# Invisible cursor theme: touch-only kiosk, we don't want the pointer
# sitting on the UI until the first touch event. labwc has no hide-always
# flag, so we point XCURSOR_THEME at a theme whose cursors are 1x1
# transparent PNGs (generated via xcursorgen).
sudo apt-get install -y x11-apps 2>&1 | tail -1  # provides xcursorgen
EMPTY_THEME="$HOME/.local/share/icons/empty"
mkdir -p "$EMPTY_THEME/cursors"
cat > "$EMPTY_THEME/index.theme" <<'EOF'
[Icon Theme]
Name=empty
Comment=Invisible cursor theme for kiosk
Inherits=default
EOF
python3 -c "
import struct, zlib
def c(t,d):
    return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + c(b'IHDR', struct.pack('>IIBBBBB',1,1,8,6,0,0,0)) \
    + c(b'IDAT', zlib.compress(b'\x00\x00\x00\x00\x00')) + c(b'IEND', b'')
open('/tmp/empty.png','wb').write(png)
"
echo '24 0 0 /tmp/empty.png' > /tmp/empty.cfg
xcursorgen /tmp/empty.cfg "$EMPTY_THEME/cursors/default"
for n in left_ptr arrow hand1 hand2 xterm crosshair watch wait text pointer grab grabbing \
         top_left_corner top_right_corner bottom_left_corner bottom_right_corner \
         n-resize s-resize e-resize w-resize ns-resize ew-resize \
         se-resize sw-resize ne-resize nw-resize fleur move size_all progress; do
    ln -sf default "$EMPTY_THEME/cursors/$n"
done

cat > "$HOME/.config/labwc/environment" <<'EOF'
XCURSOR_THEME=empty
XCURSOR_SIZE=1
EOF

# Disable lightdm (we boot to text console, not graphical).
sudo systemctl disable lightdm.service 2>/dev/null || true

# systemd-networkd's wait-online is auto-enabled when networkd is enabled,
# adding ~15 s to the boot total (not on critical path but pollutes timing).
sudo systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

# When NetworkManager is disabled, /etc/resolv.conf becomes blank (NM stops
# regenerating it; networkd doesn't touch it without systemd-resolved). Write
# a static one so DNS keeps working.
if ! grep -q "^nameserver" /etc/resolv.conf 2>/dev/null; then
    echo "nameserver 192.168.1.1" | sudo tee /etc/resolv.conf > /dev/null
fi

echo "==> Installing XDG autostart entry (legacy fallback if user reverts to lightdm)..."
# labwc / wayfire-pi parse ~/.config/autostart/*.desktop after the desktop
# session is up. Same template as the desktop shortcut — Exec points to
# run_silvia.sh which always cds to ui/source/ and launches the live files,
# so autostart automatically picks up whatever's been pushed since last boot.
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
sed "s|@PROJECT_DIR@|$PROJECT_DIR|g" "$SCRIPT_DIR/silvia.desktop.in" > "$AUTOSTART_DIR/silvia.desktop"
chmod +x "$AUTOSTART_DIR/silvia.desktop"
# Mark trusted so PCManFM/labwc file manager launches without a warning on first tap
if command -v gio >/dev/null 2>&1; then
    gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
fi
echo "    -> $DESKTOP_FILE"

echo "==> Done."
echo
echo "Log out and back in for dialout group to take effect."
echo "Then launch by tapping the Silvia Lever icon on the desktop,"
echo "or run directly:  $SCRIPT_DIR/run_silvia.sh"
echo
echo "The Teensy should enumerate as /dev/ttyACM0 (VID 0x16C0). Auto-detect handles it."
