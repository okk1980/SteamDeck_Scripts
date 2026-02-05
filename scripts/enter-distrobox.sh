#!/usr/bin/env bash
set -euo pipefail

# Helper to enter the 'garmin-stable' distrobox and start a shell in the mounted workspace
NAME=garmin-stable

if ! command -v distrobox >/dev/null 2>&1; then
  echo "distrobox CLI not found."
  exit 1
fi

echo "Entering distrobox '$NAME' and switching to /home/developer/host-workspace (if present)"
# We unset specific GTK modules that cause "Failed to load module" spam because the container lacks these KDE-specific shared objects.
# We also disable the AT-SPI bridge (NO_AT_BRIDGE=1) to suppress "unknown signature" warnings common in containers.
distrobox-enter --name "$NAME" -- bash -lc 'export GTK_MODULES=canberra-gtk-module; export NO_AT_BRIDGE=1; cd /home/developer/host-workspace 2>/dev/null || true; exec bash'
