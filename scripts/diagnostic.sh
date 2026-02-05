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
        "INFO")
            echo -e "[ ${BLUE}INFO${NC} ] $name (Value: $current)"
            ;;
    esac
    echo "----------------------------------------------------------------------"
}

# 1. Swap Size & Usage
swap_total=$(free -g | grep Swap | awk '{print $2}')
swap_used_pct=$(free | grep Swap | awk '{if ($2 > 0) print int($3 * 100 / $2); else print 0}')

if [ "$swap_total" -ge 15 ]; then
    status="GOOD"
elif [ "$swap_total" -ge 8 ]; then
    status="WARNING"
else
    status="BAD"
fi
report "$status" "Swap File Size" "HIGH: OOM crashes during compilation" "Increase swap to 16GB (e.g., via CryoUtilities)" "${swap_total}GB"

if [ "$swap_used_pct" -lt 50 ]; then
    report "GOOD" "Swap Usage" "None" "" "${swap_used_pct}%"
else
    report "WARNING" "Swap Usage" "Medium: System might feel sluggish as it hits disk" "Close unused applications" "${swap_used_pct}%"
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

# 4. UMA Frame Buffer (VRAM)
vram_raw=$(cat /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null || cat /sys/module/amdgpu/parameters/vramlimit 2>/dev/null || echo "0")
vram_mb=$(( vram_raw / 1024 / 1024 ))
vram_gb=$(( vram_mb / 1024 ))

if [ "$vram_mb" -le 512 ]; then
    report "BAD" "UMA Frame Buffer (VRAM)" "CRITICAL: Very low graphics memory causes UI lag, simulator crashes, and GPU resets" "Change in BIOS (Hold Vol+ & Power -> Setup Utility -> Advanced -> UMA Frame Buffer) to 4G" "${vram_mb}MB"
elif [ "$vram_gb" -lt 3 ]; then
    report "WARNING" "UMA Frame Buffer (VRAM)" "Medium: Simulator instability / GPU acceleration lag" "Change in BIOS (Hold Vol+ & Power -> Setup Utility -> Advanced -> UMA Frame Buffer) to 4G" "${vram_gb}GB"
else
    report "GOOD" "UMA Frame Buffer (VRAM)" "None" "" "${vram_gb}GB"
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

# 8. Disk Space
home_usage=$(df -h "$HOME" | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$home_usage" -lt 90 ]; then
    report "GOOD" "Disk Space ($HOME)" "None" "" "${home_usage}%"
else
    report "BAD" "Disk Space ($HOME)" "HIGH: System sluggishness and write failures" "Free up space on your internal storage" "${home_usage}%"
fi

# 9. ZRAM Status
if command -v zramctl >/dev/null 2>&1; then
    # Use DISKSIZE instead of LIMIT which is more compatible
    zram_info=$(zramctl --noheadings --output DATA,DISKSIZE 2>/dev/null || echo "0 0")
    read -r zram_data zram_limit <<< "$zram_info"
    
    # Convert to bytes if suffixed
    convert_to_bytes() {
        local val=$1
        val=${val//,/.}
        if [[ $val == *G ]]; then echo "${val%G}" | awk '{printf "%.0f", $1 * 1024 * 1024 * 1024}'
        elif [[ $val == *M ]]; then echo "${val%M}" | awk '{printf "%.0f", $1 * 1024 * 1024}'
        elif [[ $val == *K ]]; then echo "${val%K}" | awk '{printf "%.0f", $1 * 1024}'
        else echo "${val:-0}"; fi
    }
    
    data_b=$(convert_to_bytes "$zram_data")
    limit_b=$(convert_to_bytes "$zram_limit")
    
    if [ "${limit_b:-0}" -gt 0 ]; then
        zram_pct=$(( (data_b * 100) / limit_b ))
        if [ "$zram_pct" -lt 80 ]; then
            report "GOOD" "ZRAM Usage" "None" "" "${zram_pct}%"
        else
            report "WARNING" "ZRAM Usage" "High: System may start swapping to disk" "Close unused applications or VS Code tabs" "${zram_pct}%"
        fi
    else
        report "GOOD" "ZRAM Status" "None" "" "Not in use or size 0"
    fi
fi

# 10. IO Wait (Sluggishness detector)
# More robust extraction of IO Wait percentage
iowait_raw=$(top -bn1 | grep "Cpu(s)" | awk -F'wa' '{print $1}' | awk '{print $NF}' | sed 's/[^0-9.]//g')
iowait_int=${iowait_raw%.*}
iowait_int=${iowait_int:-0}

if [ "$iowait_int" -lt 5 ]; then
    report "GOOD" "IO Wait" "None" "" "${iowait_raw:-0}%"
else
    report "WARNING" "IO Wait" "High: Interface sluggishness, likely disk bottleneck" "Check if Steam is updating games or if SD card is slow" "${iowait_raw}%"
fi

# 11. Thermal Throttling
thermal_msg=$(sudo dmesg 2>/dev/null | grep -qi "thermal throttling" && echo "Detected" || echo "Clean")
if [ "$thermal_msg" == "Detected" ]; then
    report "BAD" "Thermal Throttling" "HIGH: CPU/GPU frequency capped" "Ensure fans are not blocked and check ambient temperature" "Detected in dmesg"
else
    report "GOOD" "Thermal Throttling" "None" "" "Not detected (or dmesg restricted)"
fi

# 12. System Logs Size
journal_size=$(journalctl --disk-usage | awk '{print $7}')
if [[ "$journal_size" == *G* ]]; then
    report "WARNING" "System Logs Size" "Low: Large logs can slow down journal queries" "Run: sudo journalctl --vacuum-time=2d" "$journal_size"
else
    report "GOOD" "System Logs Size" "None" "" "$journal_size"
fi

# 13. Inotify Instances
instances=$(cat /proc/sys/fs/inotify/max_user_instances)
if [ "$instances" -ge 512 ]; then
    report "GOOD" "Inotify Instances" "None" "" "$instances"
else
    report "WARNING" "Inotify Instances" "Low: VS Code extension host may crash" "Run: echo fs.inotify.max_user_instances=512 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p" "$instances"
fi

# 14. KDE Baloo Indexing
if pgrep -x "baloo_file" >/dev/null; then
    report "WARNING" "KDE File Indexing (Baloo)" "Low: Background CPU/IO usage" "Consider disabling if indexing is not needed (balooctl disable)" "Running"
else
    report "GOOD" "KDE File Indexing (Baloo)" "None" "" "Disabled/Not running"
fi

# 15. Load Average
load_avg=$(cut -d' ' -f1 /proc/loadavg)
cpu_count=$(nproc)
# Compare using awk since bc might be missing
is_high=$(awk -v n1="$load_avg" -v n2="$cpu_count" 'BEGIN {if (n1 > n2) print 1; else print 0}')
if [ "$is_high" -eq 0 ]; then
    report "GOOD" "System Load" "None" "" "$load_avg"
else
    report "WARNING" "System Load" "Medium: CPU cores are saturated" "Identify high CPU processes (e.g., top or htop)" "$load_avg"
fi

# 16. Heavy Development Processes (Memory Leaks)
echo -e "${BLUE}>> Top Memory Processes (Dev related):${NC}"
ps -eo pmem,comm,pid,rss --sort=-rss | grep -E "code|java|simulator|node|distrobox" | head -n 5 | while read -r pmem comm pid rss; do
    rss_mb=$(( rss / 1024 ))
    if [ "$rss_mb" -gt 2000 ]; then
        echo -e "[ ${RED}HUGE${NC} ] $comm (PID: $pid) - ${rss_mb}MB"
    elif [ "$rss_mb" -gt 1000 ]; then
        echo -e "[ ${YELLOW}HIGH${NC} ] $comm (PID: $pid) - ${rss_mb}MB"
    else
        echo -e "[ INFO ] $comm (PID: $pid) - ${rss_mb}MB"
    fi
done

# 17. Power Supply Status
if [ -f "/sys/class/power_supply/ACAD/online" ]; then
    ac_status=$(cat /sys/class/power_supply/ACAD/online)
    if [ "$ac_status" -eq 1 ]; then
        report "GOOD" "Power Supply" "None" "" "Plugged In"
    else
        report "WARNING" "Power Supply" "Medium: Performance throttling likely on battery" "Plug in your Steam Deck for full performance" "Battery Power"
    fi
fi

# 18. Trash Size
trash_size=$(du -ks "$HOME/.local/share/Trash" 2>/dev/null | awk '{print $1}')
trash_size_mb=$((trash_size / 1024))
if [ "$trash_size_mb" -gt 2048 ]; then
    report "WARNING" "Trash Size" "Low: Wasted disk space" "Empty your trash (Trash Size: ${trash_size_mb}MB)" "${trash_size_mb}MB"
else
    report "GOOD" "Trash Size" "None" "" "${trash_size_mb}MB"
fi

# 19. VS Code Extensions Count
# Check ~/.vscode/extensions directly to avoid launching the heavy 'code' wrapper/container
ext_count=0
if [ -d "$HOME/.vscode/extensions" ]; then
    ext_count=$(find "$HOME/.vscode/extensions" -maxdepth 1 -mindepth 1 -type d | wc -l)
elif [ -d "$HOME/.var/app/com.visualstudio.code/data/vscode/extensions" ]; then
    # Check Flatpak path if standard path missing
    ext_count=$(find "$HOME/.var/app/com.visualstudio.code/data/vscode/extensions" -maxdepth 1 -mindepth 1 -type d | wc -l)
elif command -v code >/dev/null 2>&1; then
    # Fallback to CLI (slow, might hang)
    ext_count=$(timeout 5s code --list-extensions 2>/dev/null | wc -l)
fi

if [ "$ext_count" -gt 0 ]; then
    if [ "$ext_count" -gt 40 ]; then
        report "WARNING" "VS Code Extensions" "Medium: High extension count can slow down editor" "Disable unused extensions" "$ext_count installed"
    else
        report "GOOD" "VS Code Extensions" "None" "" "$ext_count installed"
    fi
else
    report "GOOD" "VS Code Extensions" "None" "" "Unknown / None found"
fi

# 20. Linux Open File Descriptions Limit (ulimit)
# VS Code + Java + Compilers need a lot of file handles
ulimit_val=$(ulimit -n)
if [ "$ulimit_val" -lt 4096 ]; then
    report "WARNING" "File Descriptors (ulimit)" "High: 'Too many open files' crashes" "Run scripts/apply_opt_fixes.sh (requires reboot)" "$ulimit_val"
else
    report "GOOD" "File Descriptors (ulimit)" "None" "" "$ulimit_val"
fi

# 21. SSD Trim Timer
# Crucial for Steam Deck internal SSD performance over time
if command -v systemctl >/dev/null 2>&1; then
    trim_status=$(systemctl is-enabled fstrim.timer 2>/dev/null || echo "inactive")
    if [ "$trim_status" == "enabled" ]; then
        report "GOOD" "SSD Trim Timer" "None" "" "Enabled"
    else
        report "WARNING" "SSD Trim Timer" "Medium: degraded disk write speed over time" "Run: sudo systemctl enable --now fstrim.timer" "$trim_status"
    fi
else
    report "INFO" "SSD Trim Timer" "Unknown" "systemctl not available" "Skipped"
fi

# 22. Pacman Cache (Arch Linux specific)
if [ -d "/var/cache/pacman/pkg" ]; then
    pkg_cache_size=$(du -ks /var/cache/pacman/pkg 2>/dev/null | awk '{print $1}')
    pkg_cache_mb=$((pkg_cache_size / 1024))
    if [ "$pkg_cache_mb" -gt 4096 ]; then
        report "WARNING" "Pacman Package Cache" "Low: Wasted Disk Space" "Run: sudo pacman -Sc" "${pkg_cache_mb}MB"
    else
        report "GOOD" "Pacman Package Cache" "None" "" "${pkg_cache_mb}MB"
    fi
fi

# 23. Failed System Services
if command -v systemctl >/dev/null 2>&1; then
    # Capture stderr to avoid "System has not been booted with systemd" messages in containers
    if failed_output=$(systemctl --failed --no-legend --plain 2>/dev/null); then
        # Count lines, ensure numeric output
        failed_units=$(echo "$failed_output" | grep -c . || echo "0")
        # Strip potential newlines/whitespace
        failed_units=$(echo "$failed_units" | tr -d '[:space:]')
        
        if [ "$failed_units" -gt 0 ]; then
            report "WARNING" "Failed System Services" "High: Potential system instability" "Run: systemctl --failed" "$failed_units failed"
        else
            report "GOOD" "System Services" "None" "" "All running"
        fi
    else
         report "INFO" "System Services" "Unknown" "systemctl failed to run (container?)" "Skipped"
    fi
fi

# 24. Flatpak VS Code Permissions
# Common issue: Flatpak VS Code can't see the SDK or tools
if command -v flatpak >/dev/null 2>&1; then
    if flatpak list --app | grep -q "com.visualstudio.code"; then
        perms=$(flatpak info --show-permissions com.visualstudio.code 2>/dev/null | grep "filesystem")
        if [[ "$perms" == *"host"* ]] || [[ "$perms" == *"home"* ]]; then
             report "GOOD" "Flatpak Permissions" "None" "" "Host/Home Access Enabled"
        else
             report "WARNING" "Flatpak Permissions" "High: Terminals and SDKs won't work" "Use Flatseal to grant 'All User Files' (filesystem=host) access" "Restricted"
        fi
    fi
fi

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}   DIAGNOSTIC COMPLETE                                               ${NC}"
echo -e "${BLUE}======================================================================${NC}"
