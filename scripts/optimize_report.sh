#!/usr/bin/env bash

# Steam Deck Garmin Development Diagnostic Script
# This script checks the system and container for best practices and optimizations.
# It DOES NOT change any settings, only reports status.

set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Add common local paths to PATH for distrobox and podman
export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:$PATH"

CONTAINER_NAME="garmin-stable"

echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}   STEAM DECK GARMIN DEV OPTIMIZATION REPORT                    ${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "Target Container: ${BLUE}$CONTAINER_NAME${NC}"
echo ""

report_item() {
    local category=$1
    local check=$2
    local status=$3
    local impact=$4
    local info=$5
    local fix=$6

    local status_color=$GREEN
    [ "$status" == "BAD" ] && status_color=$RED
    [ "$status" == "WARNING" ] && status_color=$YELLOW

    echo -e "[${category}] ${BOLD}${check}${NC}"
    echo -e "  Status: ${status_color}${status}${NC}"
    echo -e "  Impact: ${impact}"
    echo -e "  Info:   ${info}"
    if [ "$status" != "GOOD" ]; then
        echo -e "  Fix:    ${fix}"
    fi
    echo ""
}

# --- HOST CHECKS ---

# 1. Swap Size
SWAP_TOTAL=$(free -g | grep Swap | awk '{print $2}')
if [ "$SWAP_TOTAL" -ge 16 ]; then
    report_item "Host" "Swap Size" "GOOD" "High" "Swap is ${SWAP_TOTAL}GB. Sufficient for heavy compilation and simulator." ""
elif [ "$SWAP_TOTAL" -ge 8 ]; then
    report_item "Host" "Swap Size" "WARNING" "High" "Swap is ${SWAP_TOTAL}GB. Recommended is 16GB for multitasking." "Use CryoUtilities or 'sudo fallocate -l 16G /home/swapfile'."
else
    report_item "Host" "Swap Size" "BAD" "High" "Swap is only ${SWAP_TOTAL}GB. System might freeze during heavy tasks." "Increase swap to 16GB using CryoUtilities or manual fallocate."
fi

# 2. Swappiness
SWAPPINESS=$(cat /proc/sys/vm/swappiness)
if [ "$SWAPPINESS" -le 10 ]; then
    report_item "Host" "Swappiness" "GOOD" "Medium" "Swappiness is ${SWAPPINESS}. System prioritizes RAM over disk." ""
else
    report_item "Host" "Swappiness" "WARNING" "Medium" "Swappiness is ${SWAPPINESS}. High swappiness can cause UI micro-stutters." "Set swappiness to 1 (CryoUtilities default) or 10."
fi

# 3. Inotify Watches (for VS Code)
INOTIFY_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches)
if [ "$INOTIFY_WATCHES" -ge 524288 ]; then
    report_item "Host" "Inotify Watches" "GOOD" "High" "Max inotify watches is ${INOTIFY_WATCHES}. VS Code can track many files." ""
else
    report_item "Host" "Inotify Watches" "BAD" "High" "Inotify limit is ${INOTIFY_WATCHES}. VS Code will fail to watch large projects." "Run: echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p"
fi

# 4. UMA Framebuffer (GPU RAM)
if [ -f /sys/class/drm/card0/device/mem_info_vram_total ]; then
    VRAM_BYTES=$(cat /sys/class/drm/card0/device/mem_info_vram_total)
    VRAM_GB=$((VRAM_BYTES / 1024 / 1024 / 1024))
    if [ "$VRAM_GB" -ge 3 ]; then # Allows for slight variations
        report_item "Host" "UMA Framebuffer" "GOOD" "Medium" "GPU VRAM is ~${VRAM_GB}GB. Recommended for Simulator." ""
    else
        report_item "Host" "UMA Framebuffer" "WARNING" "Medium" "GPU VRAM is ${VRAM_GB}GB. Default 1GB can limit Simulator performance." "Set UMA Frame Buffer Size to 4G in BIOS (Hold Vol+ and Power on boot)."
    fi
else
    report_item "Host" "UMA Framebuffer" "INFO" "Medium" "Could not detect UMA size automatically via sysfs." "Verify it is set to 4G in BIOS for stable Simulator performance."
fi

# 5. Disk Space
HOME_FREE=$(df -h /home | tail -n 1 | awk '{print $4}' | tr -d 'G')
# Handle cases where value might be in M or T or have comma
HOME_FREE_VAL=$(df -k /home | tail -n 1 | awk '{print $4}') # in KB
if [ "$HOME_FREE_VAL" -gt 20971520 ]; then # > 20GB
    report_item "Host" "Disk Space" "GOOD" "Medium" "Disk space in /home is sufficient." ""
else
    report_item "Host" "Disk Space" "WARNING" "Medium" "Disk space in /home is low. Garmin SDKs and simulators take space." "Clean up unwanted files or move SDKs to SD card."
fi

# --- CONTAINER CHECKS ---

if ! command -v distrobox > /dev/null 2>&1 || ! distrobox list | grep -qw "$CONTAINER_NAME"; then
    echo -e "${RED}Error: Distrobox '$CONTAINER_NAME' not found. Skipping container checks.${NC}"
else
    echo -e "${BOLD}Checking Distrobox '$CONTAINER_NAME'...${NC}"
    
    # Run checks inside container
    CONTAINER_REPORT=$(distrobox enter "$CONTAINER_NAME" -- bash -c "
        # Java check
        if command -v java >/dev/null 2>&1; then
            JAVA_VER=\$(java -version 2>&1 | head -n 1)
            echo \"JAVA_STATUS:GOOD:Current: \$JAVA_VER\"
        else
            echo \"JAVA_STATUS:BAD:Java is missing. Garmin SDK requires it.\"
        fi

        # libusb check
        if ldconfig -p | grep -q libusb-1.0; then
            echo \"LIBUSB_STATUS:GOOD:libusb-1.0 found.\"
        else
            echo \"LIBUSB_STATUS:BAD:libusb-1.0 missing. Device sync will fail.\"
        fi

        # GTK3 check (for Simulator)
        if ldconfig -p | grep -q libgtk-3; then
            echo \"GTK_STATUS:GOOD:GTK3 found.\"
        else
            echo \"GTK_STATUS:BAD:GTK3 missing. Simulator GUI might not start.\"
        fi

        # sqlite3 check
        if command -v sqlite3 >/dev/null 2>&1; then
            echo \"SQLITE_STATUS:GOOD:sqlite3 found.\"
        else
            echo \"SQLITE_STATUS:WARNING:sqlite3 missing. Might be needed for some SDK tools.\"
        fi

        # unzip check
        if command -v unzip >/dev/null 2>&1; then
            echo \"UNZIP_STATUS:GOOD:unzip found.\"
        else
            echo \"UNZIP_STATUS:BAD:unzip missing. SDK manager cannot extract SDKs.\"
        fi
    ")

    # Parse container report
    JAVA_STATUS=$(echo "$CONTAINER_REPORT" | grep "JAVA_STATUS" || echo "JAVA_STATUS:BAD:Unknown")
    report_item "Container" "Java Runtime" "$(echo $JAVA_STATUS | cut -d: -f2)" "CRITICAL" "$(echo $JAVA_STATUS | cut -d: -f3-)" "sudo apt install openjdk-17-jdk"

    LIBUSB_STATUS=$(echo "$CONTAINER_REPORT" | grep "LIBUSB_STATUS" || echo "LIBUSB_STATUS:BAD:Unknown")
    report_item "Container" "libusb-1.0" "$(echo $LIBUSB_STATUS | cut -d: -f2)" "HIGH" "$(echo $LIBUSB_STATUS | cut -d: -f3-)" "sudo apt install libusb-1.0-0"

    GTK_STATUS=$(echo "$CONTAINER_REPORT" | grep "GTK_STATUS" || echo "GTK_STATUS:BAD:Unknown")
    report_item "Container" "GTK3 Support" "$(echo $GTK_STATUS | cut -d: -f2)" "HIGH" "$(echo $GTK_STATUS | cut -d: -f3-)" "sudo apt install libgtk-3-0"

    SQLITE_STATUS=$(echo "$CONTAINER_REPORT" | grep "SQLITE_STATUS" || echo "SQLITE_STATUS:WARNING:Unknown")
    report_item "Container" "sqlite3" "$(echo $SQLITE_STATUS | cut -d: -f2)" "MEDIUM" "$(echo $SQLITE_STATUS | cut -d: -f3-)" "sudo apt install sqlite3"

    UNZIP_STATUS=$(echo "$CONTAINER_REPORT" | grep "UNZIP_STATUS" || echo "UNZIP_STATUS:BAD:Unknown")
    report_item "Container" "unzip" "$(echo $UNZIP_STATUS | cut -d: -f2)" "HIGH" "$(echo $UNZIP_STATUS | cut -d: -f3-)" "sudo apt install unzip"
fi

# --- VS CODE CHECKS ---

# 1. VS Code Extensions
if command -v code > /dev/null 2>&1; then
    CIQ_EXT=$(code --list-extensions | grep -i "garmin.connect-iq-vscode" || true)
    if [ -n "$CIQ_EXT" ]; then
        report_item "VS Code" "Garmin Extension" "GOOD" "High" "Connect IQ extension is installed." ""
    else
        report_item "VS Code" "Garmin Extension" "BAD" "High" "Connect IQ extension is NOT installed." "Install 'Garmin Connect IQ' from the VS Code Marketplace."
    fi
else
    report_item "VS Code" "CLI" "WARNING" "Medium" "VS Code 'code' command not in PATH." "Enable 'code' command in VS Code (Shell Command: Install 'code' command in PATH)."
fi

# 2. Wayland Support
if [ -f "$HOME/.config/code-flags.conf" ]; then
    if grep -q "ozone-platform=wayland" "$HOME/.config/code-flags.conf"; then
        report_item "VS Code" "Wayland Support" "GOOD" "Low" "Wayland flags detected. Better UI performance on Steam Deck." ""
    else
        report_item "VS Code" "Wayland Support" "WARNING" "Low" "Ozone flags missing. VS Code might run via XWayland (blurry/lags)." "Add --enable-features=UseOzonePlatform --ozone-platform=wayland to ~/.config/code-flags.conf"
    fi
else
    report_item "VS Code" "Wayland Support" "WARNING" "Low" "code-flags.conf not found." "Create ~/.config/code-flags.conf with Wayland flags for smoother UI."
fi

echo -e "${BOLD}================================================================${NC}"
echo -e "Diagnostic Complete."
echo -e "Note: These recommendations are based on community best practices for"
echo -e "Steam Deck power users and Garmin developers (Connect IQ)."
echo -e "${BOLD}================================================================${NC}"
