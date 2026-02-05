#!/usr/bin/env bash
set -euo pipefail

# Run this inside the distrobox (or enter it and run this script).
# Installs a minimal set of dev packages and tools helpful on Steam Deck (Ubuntu LTS base).

echo "Updating package index and installing common dev packages (requires sudo inside container)."

if command -v apt >/dev/null 2>&1; then
  sudo apt update
  # Added libcanberra-gtk* to fix "Failed to load module" GTK warnings in SDK Manager
  sudo apt install -y build-essential git curl wget ca-certificates python3 python3-venv python3-pip \
    pkg-config libssl-dev cmake unzip libusb-1.0-0 default-jre \
    libcanberra-gtk-module libcanberra-gtk3-module
  echo "Installed apt-packages (including libusb, Java, and GTK modules for Garmin development)."
else
  echo "Non-apt distro detected. Please install your preferred packages manually."
fi

echo "If you plan to run VS Code GUI from the host, use the host's VS Code and the mounted workspace.
For remote GUI support or additional tools, install them manually as needed."

exit 0
