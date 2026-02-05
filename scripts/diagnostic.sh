#!/usr/bin/env bash
# ==============================================================================
# Steam Deck Development Diagnostic Script
# specifically for VS Code & Garmin SDK in Distrobox (Ubuntu)
# ==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONTAINER_NAME="garmin-stable"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}   STEAM DECK DEVELOPMENT DIAGNOSTIC                                  ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# Helper function to report status
report() {
    local status=$1
    local name=$2
    local impact=$3
    local fix=$4
    local current=$5

    case $status in
        "GOOD")
            echo -e "[ ${GREEN}GOOD${NC} ] $name (Value: $current)"
            ;;
        "WARNING")
            echo -e "[ ${YELLOW}WARN${NC} ] $name (Value: $current)"
            echo -e "         Impact: $impact"
            echo -e "         Fix   : $fix"
            ;;
        "BAD")
            echo -e "[ ${RED}BAD ${NC} ] $name (Value: $current)"
            echo -e "         Impact: $impact"
            echo -e "         Fix   : $fix"
            ;;
    esac
    echo "----------------------------------------------------------------------"
}

# 1. Swap Size
swap_total=$(free -g | grep Swap | awk '{print $2}')
if [ "$swap_total" -ge 15 ]; then
    report "GOOD" "Swap File Size" "None" "" "${swap_total}GB"
elif [ "$swap_total" -ge 8 ]; then
    report "WARNING" "Swap File Size" "Low" "Consider increasing to 16GB for heavy builds" "${swap_total}GB"
else
    report "BAD" "Swap File Size" "HIGH: OOM crashes during compilation" "Increase swap to 16GB (e.g., via CryoUtilities)" "${swap_total}GB"
fi

# 2. Swappiness
swappiness=$(cat /proc/sys/vm/swappiness)
if [ "$swappiness" -le 10 ]; then
    report "GOOD" "Swappiness" "None" "" "$swappiness"
else
    report "WARNING" "Swappiness" "Medium: UI stutter when memory is full" "Set swappiness to 1 (sudo sysctl vm.swappiness=1)" "$swappiness"
fi

# 3. Inotify Watches
inotify=$(cat /proc/sys/fs/inotify/max_user_watches)
if [ "$inotify" -ge 524288 ]; then
    report "GOOD" "Inotify Watches" "None" "" "$inotify"
else
    report "BAD" "Inotify Watches" "HIGH: VS Code cannot track file changes in large projects" "Run: echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p" "$inotify"
fi

# 4. UMA Frame Buffer (VRAM) - Approximate check via dmesg/vram_size
# Steam Deck default is 1G, recommended 4G for simulator stability
vram_raw=$(cat /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null || echo "0")
vram_gb=$(( vram_raw / 1024 / 1024 / 1024 ))
if [ "$vram_gb" -ge 3 ]; then
    report "GOOD" "UMA Frame Buffer (VRAM)" "None" "" "${vram_gb}GB"
else
    report "WARNING" "UMA Frame Buffer (VRAM)" "Medium: Simulator instability/GPU crashes" "Change in BIOS (Hold Vol+ & Power -> Setup Utility -> Advanced -> UMA Frame Buffer)" "${vram_gb}GB"
fi

# 5. CPU Governor
governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
if [ "$governor" == "performance" ]; then
    report "GOOD" "CPU Governor" "None" "" "$governor"
else
    report "WARNING" "CPU Governor" "Low: Slower compilation" "Switch to 'Performance' in Desktop Mode power settings if plugged in" "$governor"
fi

# 6. Check for Garmin SDK / Linux Requirements inside Distrobox
if command -v distrobox >/dev/null 2>&1; then
    if distrobox list | grep -q "$CONTAINER_NAME"; then
        echo -e "${BLUE}>> Checking Container: $CONTAINER_NAME${NC}"
        
        # Check Java
        java_check=$(distrobox enter "$CONTAINER_NAME" -- bash -c "java -version 2>&1 | head -n 1" || echo "Missing")
        if [[ "$java_check" == *"version"* ]] || [[ "$java_check" == *"runtime"* ]]; then
            report "GOOD" "Java Environment" "None" "" "$java_check"
        else
            report "BAD" "Java Environment" "CRITICAL: Garmin Monkey C compiler requires Java" "Run: sudo apt install openjdk-17-jdk (inside container)" "$java_check"
        fi

        # Check libusb
        libusb_check=$(distrobox enter "$CONTAINER_NAME" -- bash -c "dpkg -l | grep libusb-1.0-0 | awk '{print \$3}'" || echo "")
        if [ -n "$libusb_check" ]; then
            report "GOOD" "libusb-1.0-0" "None" "" "$libusb_check"
        else
            report "BAD" "libusb-1.0-0" "HIGH: Simulator and Device communication will fail" "Run: sudo apt install libusb-1.0-0 (inside container)" "Missing"
        fi
    else
        report "WARNING" "Distrobox Container" "High" "Container '$CONTAINER_NAME' not found. Garmin dev requires it." "Run create-distrobox.sh" "Missing"
    fi
else
    report "BAD" "Distrobox" "High" "Distrobox is not installed." "Install Distrobox using the provided scripts or your package manager." "Not found"
fi

# 7. VS Code Ozone Flags (Wayland Performance)
if [ -f "$HOME/.config/code-flags.conf" ]; then
    if grep -q "UseOzonePlatform" "$HOME/.config/code-flags.conf"; then
        report "GOOD" "VS Code Wayland Flags" "None" "" "Present"
    else
        report "WARNING" "VS Code Wayland Flags" "Low: Blurry UI / Better performance" "Add --enable-features=UseOzonePlatform --ozone-platform=wayland to ~/.config/code-flags.conf" "Missing flags"
    fi
else
    report "WARNING" "VS Code Wayland Flags" "Low" "code-flags.conf file not found. VS Code might be running in XWayland." "Create ~/.config/code-flags.conf with Wayland flags" "File missing"
fi

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}   DIAGNOSTIC COMPLETE                                               ${NC}"
echo -e "${BLUE}======================================================================${NC}"
