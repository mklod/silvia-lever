#!/bin/bash
# Last modified: 2026-04-17--0020
# Launcher for Silvia UI on Raspberry Pi. Fullscreen + 2x scaling applied
# automatically by platform_shim.py.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../source"

# Wayland env fallback (for launches from SSH without desktop env inherited)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"

cd "$SOURCE_DIR"
exec python3 run_silvia.py "$@"
