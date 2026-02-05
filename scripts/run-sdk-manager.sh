#!/usr/bin/env bash
set -e

# This script launches the Garmin SDK Manager with the correct environment settings
# to suppress GTK and ATK warnings. It works from both Host and Container.

CONTAINER_NAME="garmin-stable"
SDK_BIN_PATH="$HOME/garmin-sdk/bin/sdkmanager"

# 1. Determine if we are in the container
if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
    IN_CONTAINER=true
else
    IN_CONTAINER=false
fi

# 2. Define the launch command with environment fixes
# Use 'env' to strictly set the variables for the process
# We set both GTK_MODULES (GTK2) and GTK3_MODULES (GTK3) just in case
CMD="env GTK_MODULES=canberra-gtk-module GTK3_MODULES=canberra-gtk-module NO_AT_BRIDGE=1 $SDK_BIN_PATH"

if [ "$IN_CONTAINER" = true ]; then
    echo ">> [Container] Launching SDK Manager..."
    if [ -f "$SDK_BIN_PATH" ]; then
        # Filter out known cosmetic noise from stderr, keep the rest
        bash -c "$CMD" 2> >(grep -v -E "Gtk-Message:.*Failed to load module|atk-bridge" >&2)
    else
        echo "Error: sdkmanager not found at $SDK_BIN_PATH"
        exit 1
    fi
else
    echo ">> [Host] Proxying to Distrobox '$CONTAINER_NAME'..."
    if command -v distrobox >/dev/null 2>&1; then
        # Check if container exists
        if distrobox list | grep -q "$CONTAINER_NAME"; then
            distrobox-enter --name "$CONTAINER_NAME" -- bash -lc "$CMD" 
        else
            echo "Error: Container '$CONTAINER_NAME' not found. Run create-distrobox.sh first."
            exit 1
        fi
    else
        echo "Error: Distrobox not installed."
        exit 1
    fi
fi
