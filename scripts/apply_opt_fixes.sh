#!/usr/bin/env bash
set -e

echo "Applying System Fixes..."

# 1. SSD Trim (fstrim.timer)
echo "[Fixing] Enabling SSD Trim Timer..."
if ! systemctl is-enabled fstrim.timer >/dev/null 2>&1; then
  sudo systemctl enable --now fstrim.timer
  echo "✅ fstrim.timer enabled."
else
  echo "✅ fstrim.timer was already enabled."
fi

# 2. File Descriptors (ulimit)
# On SteamOS/Arch, we can set this in a limits.d file.
LIMITS_FILE="/etc/security/limits.d/99-vscode-dev.conf"
echo "[Fixing] Increasing file descriptor limits in $LIMITS_FILE..."

if [ ! -f "$LIMITS_FILE" ] || ! grep -q "nofile 524288" "$LIMITS_FILE"; then
  echo "*       hard    nofile  524288" | sudo tee "$LIMITS_FILE" >/dev/null
  echo "*       soft    nofile  524288" | sudo tee -a "$LIMITS_FILE" >/dev/null
  echo "✅ Limits configuration created. (Reboot required to apply fully)"
else
  echo "✅ Limits configuration already exists."
fi

echo "=================================================="
echo "Fixes applied. Please REBOOT your Steam Deck."
echo "=================================================="
