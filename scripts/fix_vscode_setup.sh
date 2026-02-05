#!/usr/bin/env bash
# This script addresses VS Code CLI and Wayland performance issues on Steam Deck.
# It ensures 'code' is in the PATH and configures Wayland flags for smoother UI.

set -e

CONTAINER_NAME="garmin-stable"

# Add common local paths to PATH for this script session
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:$PATH"

echo "================================================================"
echo "   APPLYING VS CODE OPTIMIZATIONS FOR GARMIN DEV                "
echo "================================================================"

# 1. Fix: VS Code 'code' command not in PATH
echo ">> Step 1: Configuring CLI access..."

if command -v code >/dev/null 2>&1; then
    echo "   [Status] 'code' command is already available."
else
    # Try to find it in common locations or export from distrobox
    HOST_CODE=$(find /usr/bin /usr/share/code/bin /opt -name code -type f -executable 2>/dev/null | head -n 1 || true)
    
    if [ -n "$HOST_CODE" ]; then
        echo "   [Action] Found host VS Code at $HOST_CODE. Creating symlink..."
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOST_CODE" "$HOME/.local/bin/code"
        echo "   [Done] Created symlink at ~/.local/bin/code"
    elif command -v distrobox >/dev/null 2>&1; then
        echo "   [Action] Host VS Code not found. Attempting to export from '$CONTAINER_NAME'..."
        if distrobox list | grep -q "$CONTAINER_NAME"; then
            # Export the binary specifically for CLI usage
            distrobox enter "$CONTAINER_NAME" -- distrobox-export --bin /usr/bin/code --export-path "$HOME/.local/bin"
            echo "   [Done] Exported 'code' binary from container to ~/.local/bin/code"
        else
            echo "   [Warning] Distrobox '$CONTAINER_NAME' not found. Cannot export CLI."
        fi
    else
        echo "   [Error] Could not locate VS Code. Please ensure it is installed."
    fi
fi

# Ensure ~/.local/bin is in PATH in .bashrc if not already
if ! echo "$PATH" | grep -q "$HOME/.local/bin" || ! grep -q ".local/bin" "$HOME/.bashrc"; then
    echo "   [Action] Adding ~/.local/bin to PATH in ~/.bashrc..."
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "   [Done] PATH updated. You may need to restart your terminal."
fi

# 2. Fix: Wayland Support (code-flags.conf)
echo ">> Step 2: Configuring Wayland support (Ozone flags)..."

FLAGS_DIR="$HOME/.config"
FLAGS_FILE="$FLAGS_DIR/code-flags.conf"

mkdir -p "$FLAGS_DIR"

# Write flags for better performance on Steam Deck Desktop Mode (Wayland)
cat <<EOF > "$FLAGS_FILE"
--enable-features=UseOzonePlatform
--ozone-platform=wayland
--enable-gpu-rasterization
--enable-zero-copy
EOF

echo "   [Done] Created $FLAGS_FILE."
echo "   [Info] These flags reduce UI lag and prevent blurriness on Steam Deck."

echo "================================================================"
echo "   FIXES APPLIED SUCCESSFULLY                                   "
echo "   Note: Please restart VS Code (Close and Reopen) to apply.    "
echo "================================================================"
