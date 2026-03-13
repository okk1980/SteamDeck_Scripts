#!/usr/bin/env bash
# garmin_simulator_check.sh
# Checks if Garmin SDK Simulator is running and if AMD hardware is present or bypassed

set -euo pipefail

# Check if running inside Distrobox (container)
if [ ! -f /run/.containerenv ] && [ ! -f /.dockerenv ]; then
    echo "[ERROR] This script must be run inside a Distrobox/container environment."
    exit 1
fi


# Check for AMD hardware
echo "Checking for AMD hardware..."
if ! command -v lspci >/dev/null 2>&1; then
    echo "[ERROR] 'lspci' command not found. Please install pciutils inside your container:"
    echo "        sudo apt-get update && sudo apt-get install pciutils"
    AMD_PRESENT=unknown
else
    if lspci | grep -i 'VGA' | grep -qi 'AMD'; then
        echo "[INFO] AMD GPU detected."
        AMD_PRESENT=true
    else
        echo "[INFO] AMD GPU NOT detected."
        AMD_PRESENT=false
    fi
fi


# Check if Garmin SDK Simulator is running
SIM_PROC=$(pgrep -ax simulator.real) || true
if [ -n "$SIM_PROC" ]; then
    echo "[INFO] Garmin SDK simulator.real is running:"
    echo "$SIM_PROC"

    # Check if simulator is using GPU libraries
    SIM_PID=$(echo "$SIM_PROC" | awk '{print $1; exit}')
    GPU_LIBS=$(tr '\0' '\n' < /proc/$SIM_PID/maps 2>/dev/null | grep -E 'libGL|libvulkan|amdgpu|radeon' || true)
    if [ -n "$GPU_LIBS" ]; then
        echo "[INFO] Simulator process appears to be using GPU libraries:"
        echo "$GPU_LIBS"
    else
        echo "[WARNING] No GPU libraries detected in simulator process. It may be running on CPU only."
    fi
else
    echo "[INFO] Garmin SDK Simulator is NOT running."
fi

# Bypass logic (example: set env var or print warning)
if [ "$AMD_PRESENT" = false ]; then
    echo "[WARNING] AMD hardware not detected. If required, consider using a bypass or compatibility layer."
    # Example: export LD_PRELOAD or run workaround here
elif [ "$AMD_PRESENT" = unknown ]; then
    echo "[WARNING] Could not check for AMD hardware due to missing 'lspci'."
fi
