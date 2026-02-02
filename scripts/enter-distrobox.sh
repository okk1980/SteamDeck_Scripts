#!/usr/bin/env bash
set -euo pipefail

# Helper to enter the 'garmin-stable' distrobox and start a shell in the mounted workspace
NAME=garmin-stable

if ! command -v distrobox >/dev/null 2>&1; then
  echo "distrobox CLI not found."
  exit 1
fi

echo "Entering distrobox '$NAME' and switching to /home/developer/host-workspace (if present)"
distrobox-enter --name "$NAME" -- bash -lc 'cd /home/developer/host-workspace 2>/dev/null || true; exec bash'
