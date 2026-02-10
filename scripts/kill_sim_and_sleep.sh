#!/usr/bin/env bash
# ==============================================================================
# Kill Garmin Simulator and Suspend Steam Deck
# Use this when the simulator hangs or before sleeping to prevent GPU deadlocks
# ==============================================================================

SIMULATOR_NAME="simulator"

echo "Checking for running simulator..."

# Check if simulator is running
if pgrep -x "$SIMULATOR_NAME" > /dev/null; then
    echo "Simulator found. Terminating forcefully..."
    # Kill the process (forcefully with -9 to ignore hang states)
    pkill -9 -x "$SIMULATOR_NAME"
    
    # Wait up to 5 seconds for it to disappear
    timeout=5
    while pgrep -x "$SIMULATOR_NAME" > /dev/null && [ $timeout -gt 0 ]; do
        sleep 1
        ((timeout--))
    done

    if pgrep -x "$SIMULATOR_NAME" > /dev/null; then
        echo "⚠️ Warning: Simulator process is stuck and could not be killed."
    else
        echo "✅ Simulator terminated successfully."
    fi
else
    echo "ℹ️ Simulator is not running."
fi

# Sync filesystem buffers to disk to prevent data loss if the system hangs during sleep
echo "Syncing filesystems..."
sync

echo "💤 Initiating system suspend..."
# Suspend the system
systemctl suspend
