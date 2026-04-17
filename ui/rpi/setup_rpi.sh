#!/bin/bash
# Last modified: 2026-04-17--0033
# One-time setup for Raspberry Pi deployment.
# Tested target: RPi 4/5 with 1080p touchscreen, Raspberry Pi OS (Bookworm).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Installing system packages..."
sudo apt-get update
sudo apt-get install -y \
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
