#!/usr/bin/env bash
set -eu

EXT_FILE="$(dirname "$0")/../extensions.txt"
if [ ! -f "$EXT_FILE" ]; then
  echo "extensions.txt not found at $EXT_FILE"
  exit 1
fi

if command -v code >/dev/null 2>&1; then
  CLI=code
elif command -v codium >/dev/null 2>&1; then
  CLI=codium
else
  echo "VS Code CLI not found. Ensure 'code' is on PATH (install VS Code and restart shell)."
  exit 1
fi

while IFS= read -r ext || [ -n "$ext" ]; do
  ext_trimmed="$(echo "$ext" | sed 's/^\s*//;s/\s*$//')"
  [ -z "$ext_trimmed" ] && continue
  echo "Installing $ext_trimmed"
  "$CLI" --install-extension "$ext_trimmed" || echo "Failed to install $ext_trimmed"
done < "$EXT_FILE"

echo "Extensions installation finished."