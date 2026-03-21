#!/bin/bash

set -e

echo "🔄 Updating system..."
sudo apt update && sudo apt upgrade -y

echo "📦 Installing system dependencies..."
sudo apt install -y \
  python3 python3-pip python3-venv \
  qt6-base-dev qt6-declarative-dev \
  qml-module-qtquick-controls \
  qml-module-qtquick-controls2 \
  qml-module-qtquick-shapes \
  python3-pyqt6 pyqt6-dev-tools python3-serial \
  libqt6qml6 \
  python3-pyqt6.qtqml python3-pyqt6.qtquick \
  qml6-module-qtquick qml6-module-qtquick-window \
  qml6-module-qtquick-layouts qml6-module-qtquick-controls \
  qml6-module-qtquick-templates \
  qml6-module-qtqml-workerscript \
  qt6-svg-dev \
  libxcb-xinerama0 libxcb1 libx11-6 libxext6 libxrender1 \
  libxcb-render0 libxcb-shape0 libxcb-xfixes0 libxcb-shm0 \
  libxkbcommon0 libxkbcommon-x11-0 \
  libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
  libxcb-render-util0 libxcb-util1 libxcb-xkb1 libxcb-cursor0 \
  qtwayland5

echo "🐍 Creating virtual environment..."
python3 -m venv .venv --system-site-packages
source .venv/bin/activate

echo "📦 Installing Python packages..."
pip install --upgrade pip
pip install pyserial pyinstaller

echo "🚧 Building the app with PyInstaller..."
pyinstaller --noconfirm --onefile --windowed \
  --add-data "main.qml:." \
  --add-data "controls:controls" \
  --add-data "svgs:svgs" \
  run_silvia.py

echo "✅ Build complete."

export DISPLAY=:0

# Optional: Test run
echo "🚀 Running the app for testing..."
python run_silvia.py

echo "🧪 Running the compiled binary..."
./dist/run_silvia

echo "🎉 Done!"
