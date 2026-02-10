#!/usr/bin/env bash
# ==============================================================================
# Comprehensive Steam Deck Development Diagnostic & Fix Script
# ==============================================================================

# --- Configuration ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONTAINER_NAME="garmin-stable"
NEEDS_REBOOT=false
FIX_APPLIED=false

# --- Helper Functions ---

# Ask for confirmation
ask_confirm() {
    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
            [Yy]* ) return 0;; 
            [Nn]* ) return 1;; 
            * ) return 1;; 
        esac
    done
}

# Report status of a check
report() {
    local status="$1"
    local name="$2"
    local impact="$3"
    local fix_suggestion="$4"
    local current="$5"
    local fix_function="${6:-}"

    case $status in
        "GOOD") echo -e "[ ${GREEN}GOOD${NC} ] $name (Value: $current)" ;; 
        "WARNING")
            echo -e "[ ${YELLOW}WARN${NC} ] $name (Value: $current)"
            echo -e "         Impact: $impact"
            echo -e "         Fix   : $fix_suggestion"
            ;; 
        "BAD")
            echo -e "[ ${RED}BAD ${NC} ] $name (Value: $current)"
            echo -e "         Impact: $impact"
            echo -e "         Fix   : $fix_suggestion"
            ;; 
        "INFO") echo -e "[ ${BLUE}INFO${NC} ] $name (Value: $current)" ;; 
    esac

    if [[ -n "$fix_function" && "$status" != "GOOD" ]]; then
        if ask_confirm "       -> Do you want to apply the fix for '$name'?"; then
            "$fix_function"
            FIX_APPLIED=true
        else
            echo -e "       -> Skipped fix for '$name'."
        fi
    fi
    echo "----------------------------------------------------------------------"
}

# --- Fix Functions ---

_report_fix() { echo -e "         [ ${GREEN}FIXED${NC} ] $1"; }
_report_info() { echo -e "         [ ${BLUE}INFO${NC}  ] $1"; }

fix_inotify() {
    _report_info "Increasing inotify watches/instances and setting swappiness..."
    {
        echo "fs.inotify.max_user_watches=524288"
        echo "fs.inotify.max_user_instances=512"
        echo "vm.swappiness=1"
    } | sudo tee /etc/sysctl.d/99-vscode-dev.conf > /dev/null
    sudo sysctl -p --system > /dev/null
    _report_fix "Increased inotify/swappiness settings. Reboot recommended."
    NEEDS_REBOOT=true
}

fix_swappiness() {
    _report_info "Setting swappiness to 1..."
    echo "vm.swappiness=1" | sudo tee -a /etc/sysctl.d/99-vscode-dev.conf > /dev/null
    sudo sysctl vm.swappiness=1 > /dev/null
    _report_fix "Set swappiness to 1."
}

fix_ulimit() {
    _report_info "Applying file descriptor limits (ulimit)..."
    local LIMITS_FILE="/etc/security/limits.d/99-vscode-dev.conf"
    echo "* hard nofile 524288" | sudo tee "$LIMITS_FILE" > /dev/null
    echo "* soft nofile 524288" | sudo tee -a "$LIMITS_FILE" > /dev/null
    for profile in "$HOME/.bash_profile" "$HOME/.bashrc"; do
        if ! grep -q "ulimit -n 524288" "$profile" 2>/dev/null; then
            echo -e "\nulimit -n 524288" >> "$profile"
        fi
    done
    _report_fix "Set ulimit via limits.d and user profiles. Reboot required."
    NEEDS_REBOOT=true
}

fix_ssd_trim() {
    _report_info "Enabling SSD Trim Timer..."
    sudo systemctl enable --now fstrim.timer
    _report_fix "fstrim.timer has been enabled."
}

fix_baloo() {
    _report_info "Disabling KDE Baloo File Indexer..."
    balooctl disable
    _report_fix "Baloo has been disabled."
}

fix_vscode_wayland_flags() {
    _report_info "Applying VS Code Wayland flags..."
    mkdir -p "$HOME/.config"
    echo -e "\n--enable-features=UseOzonePlatform\n--ozone-platform=wayland" >> "$HOME/.config/code-flags.conf"
    _report_fix "Added Wayland flags to ~/.config/code-flags.conf."
}

fix_vscode_custom_titlebar() {
    _report_info "Setting VS Code titleBarStyle to custom..."
    local settings_file="$HOME/.config/Code/User/settings.json"
    if [ ! -f "$settings_file" ]; then
         mkdir -p "$(dirname "$settings_file")"
         echo '{
    "window.titleBarStyle": "custom"
}' > "$settings_file"
    else
        if grep -q "\"window.titleBarStyle\"" "$settings_file"; then
            sed -i 's/"window.titleBarStyle":.*/"window.titleBarStyle": "custom",/' "$settings_file"
        else
            sed -i '1s/^{/{\n    "window.titleBarStyle": "custom",/' "$settings_file"
        fi
    fi
    _report_fix "Set window.titleBarStyle to custom."
}

fix_vscode_gpu_disable() {
    _report_info "Disabling VS Code Hardware Acceleration..."
    local argv_file="$HOME/.vscode/argv.json"
    if [ ! -f "$argv_file" ]; then
        mkdir -p "$(dirname "$argv_file")"
        echo '{
    "disable-hardware-acceleration": true
}' > "$argv_file"
    else
        # Uncomment if commented
        sed -i 's|^[[:space:]]*//[[:space:]]*"disable-hardware-acceleration"|"disable-hardware-acceleration"|' "$argv_file"
        
        if grep -q "\"disable-hardware-acceleration\"" "$argv_file"; then
             sed -i 's/"disable-hardware-acceleration":.*/"disable-hardware-acceleration": true,/' "$argv_file"
        else
             # Insert before last line (assuming last line is })
             sed -i '$i \    "disable-hardware-acceleration": true,' "$argv_file"
        fi
    fi
    _report_fix "Disabled Hardware Acceleration (argv.json)."
}

fix_journal_logs() {
    _report_info "Vacuuming systemd journal logs..."
    sudo journalctl --vacuum-time=2d
    _report_fix "Journal logs vacuumed."
}

fix_pacman_cache() {
    _report_info "Cleaning Pacman cache..."
    sudo pacman -Sc --noconfirm
    _report_fix "Pacman cache cleaned."
}

fix_trash() {
    _report_info "Emptying user trash..."
    rm -rf "$HOME/.local/share/Trash/files/"*
    rm -rf "$HOME/.local/share/Trash/info/"*
    _report_fix "Trash emptied."
}

fix_flatpak_perms() {
    _report_info "Applying host filesystem permissions to Flatpak VS Code..."
    sudo flatpak override --filesystem=host com.visualstudio.code
    _report_fix "Granted host filesystem access to Flatpak VS Code."
}

fix_distrobox_libs() {
    _report_info "Installing required libraries in '$CONTAINER_NAME'..."
    local LIBS="openjdk-17-jdk libusb-1.0-0 libgtk-3-0 libxtst6 libnss3 libasound2"
    distrobox enter "$CONTAINER_NAME" -- sudo apt-get update
    distrobox enter "$CONTAINER_NAME" -- sudo apt-get install -y $LIBS
    _report_fix "Installed required libraries in the container."
}

# --- Main Logic ---
echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}   STEAM DECK DEVELOPMENT DIAGNOSTIC & FIXER                          ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# --- HOST CHECKS ---
echo -e "${BLUE}--- Host System Checks (SteamOS) ---${NC}"

# 1. Swap File Size
swap_total=$(free -g | grep Swap | awk '{print $2}')
if [ "$swap_total" -ge 15 ]; then
    status="GOOD"
elif [ "$swap_total" -ge 8 ]; then
    status="WARNING"
else
    status="BAD"
fi
report "$status" "Swap File Size" "HIGH: OOM crashes during compilation" "Increase swap to 16GB (e.g., via CryoUtilities)" "${swap_total}GB"

# 2. Swap Usage
swap_used_pct=$(free | grep Swap | awk '{if ($2 > 0) print int($3 * 100 / $2); else print 0}')
if [ "$swap_used_pct" -lt 50 ]; then
    status="GOOD"
else
    status="WARNING"
fi
report "$status" "Swap Usage" "Medium: System might feel sluggish as it hits disk" "Close unused applications" "${swap_used_pct}%"

# 3. Swappiness
swappiness=$(cat /proc/sys/vm/swappiness)
if [ "$swappiness" -le 10 ]; then
    status="GOOD"
else
    status="WARNING"
fi
report "$status" "Swappiness" "Medium: UI stutter when memory is full" "Set swappiness to 1" "$swappiness" "fix_swappiness"

# 4. Inotify Watches
inotify=$(cat /proc/sys/fs/inotify/max_user_watches)
if [ "$inotify" -ge 524288 ]; then
    status="GOOD"
else
    status="BAD"
fi
report "$status" "Inotify Watches" "HIGH: VS Code cannot track file changes in large projects" "Run: echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p" "$inotify" "fix_inotify"

# 5. UMA Frame Buffer (VRAM)
vram_raw=$(cat /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null || cat /sys/module/amdgpu/parameters/vramlimit 2>/dev/null || echo "0")
vram_mb=$(( vram_raw / 1024 / 1024 ))
vram_gb=$(( vram_mb / 1024 ))
if [ "$vram_mb" -le 512 ]; then
    status="BAD"
elif [ "$vram_gb" -lt 3 ]; then
    status="WARNING"
else
    status="GOOD"
fi
report "$status" "UMA Frame Buffer (VRAM)" "CRITICAL: Very low graphics memory causes UI lag, simulator crashes, and GPU resets" "Change in BIOS (Hold Vol+ & Power -> Setup Utility -> Advanced -> UMA Frame Buffer) to 4G" "${vram_gb}GB"

# 6. CPU Governor
governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
if [ "$governor" == "performance" ]; then
    status="GOOD"
else
    status="WARNING"
fi
report "$status" "CPU Governor" "Low: Slower compilation" "Switch to 'Performance' in Desktop Mode power settings if plugged in" "$governor"

# 7. VS Code Ozone Flags (Wayland Performance)
if [ -f "$HOME/.config/code-flags.conf" ]; then
    if grep -q "UseOzonePlatform" "$HOME/.config/code-flags.conf"; then
        status="GOOD"
        current="Present"
    else
        status="WARNING"
        current="Missing flags"
    fi
else
    status="WARNING"
    current="File missing"
fi
report "$status" "VS Code Wayland Flags" "Low: Blurry UI / Better performance" "Add --enable-features=UseOzonePlatform --ozone-platform=wayland to ~/.config/code-flags.conf" "$current" "fix_vscode_wayland_flags"

# 7a. VS Code TitleBar Style
settings_file="$HOME/.config/Code/User/settings.json"
titlebar_style="native"
if [ -f "$settings_file" ]; then
    if grep -q "\"window.titleBarStyle\":[[:space:]]*\"custom\"" "$settings_file"; then
        titlebar_style="custom"
    fi
fi
if [ "$titlebar_style" == "custom" ]; then
    status="GOOD"
else
    status="BAD"
fi
report "$status" "VS Code TitleBar Style" "HIGH: Fixes black screen rendering issues" "Set \"window.titleBarStyle\": \"custom\" in settings.json" "$titlebar_style" "fix_vscode_custom_titlebar"

# 7b. VS Code GPU Acceleration
argv_file="$HOME/.vscode/argv.json"
gpu_accel="enabled"
if [ -f "$argv_file" ]; then
    if grep -E "^[[:space:]]*\"disable-hardware-acceleration\":[[:space:]]*true" "$argv_file" >/dev/null; then
        gpu_accel="disabled"
    fi
fi
if [ "$gpu_accel" == "disabled" ]; then
    status="GOOD"
else
    status="BAD"
fi
report "$status" "VS Code GPU Acceleration" "CRITICAL: Fixes GPU crashes (Code 132/512)" "Set \"disable-hardware-acceleration\": true in argv.json" "$gpu_accel" "fix_vscode_gpu_disable"

# 8. Disk Space
home_usage=$(df -h "$HOME" | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$home_usage" -lt 90 ]; then
    status="GOOD"
else
    status="BAD"
fi
report "$status" "Disk Space ($HOME)" "HIGH: System sluggishness and write failures" "Free up space on your internal storage" "${home_usage}%"

# 9. ZRAM Status
if command -v zramctl >/dev/null 2>&1; then
    zram_info=$(zramctl --noheadings --output DATA,DISKSIZE 2>/dev/null || echo "0 0")
    read -r zram_data zram_limit <<< "$zram_info"
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
            status="GOOD"
        else
            status="WARNING"
        fi
        report "$status" "ZRAM Usage" "High: System may start swapping to disk" "Close unused applications or VS Code tabs" "${zram_pct}%"
    else
        report "GOOD" "ZRAM Status" "None" "" "Not in use or size 0"
    fi
fi

# 10. IO Wait (Sluggishness detector)
iowait_raw=$(top -bn1 | grep "Cpu(s)" | awk -F, '{print $5}' | sed 's/..wa//' | xargs)
iowait_int=${iowait_raw%.*}
iowait_int=${iowait_int:-0}
if [ "$iowait_int" -lt 5 ]; then
    status="GOOD"
else
    status="WARNING"
fi
report "$status" "IO Wait" "High: Interface sluggishness, likely disk bottleneck" "Check if Steam is updating games or if SD card is slow" "${iowait_raw}%"

# 11. Thermal Throttling
thermal_msg=$(sudo dmesg 2>/dev/null | grep -qi "thermal throttling" && echo "Detected" || echo "Clean")
if [ "$thermal_msg" == "Detected" ]; then
    status="BAD"
else
    status="GOOD"
fi
report "$status" "Thermal Throttling" "HIGH: CPU/GPU frequency capped" "Ensure fans are not blocked and check ambient temperature" "Detected in dmesg"

# 12. System Logs Size
journal_size=$(journalctl --disk-usage | awk '{print $7}')
if [[ "$journal_size" == *G* ]]; then
    status="WARNING"
else
    status="GOOD"
fi
report "$status" "System Logs Size" "Low: Large logs can slow down journal queries" "Run: sudo journalctl --vacuum-time=2d" "$journal_size" "fix_journal_logs"

# 13. Inotify Instances
instances=$(cat /proc/sys/fs/inotify/max_user_instances)
if [ "$instances" -ge 512 ]; then
    status="GOOD"
else
    status="WARNING"
fi
report "$status" "Inotify Instances" "Low: VS Code extension host may crash" "Run: echo fs.inotify.max_user_instances=512 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p" "$instances" "fix_inotify"

# 14. KDE File Indexing (Baloo)
if pgrep -x "baloo_file" >/dev/null; then
    status="WARNING"
    current="Running"
else
    status="GOOD"
    current="Disabled/Not running"
fi
report "$status" "KDE File Indexing (Baloo)" "Low: Background CPU/IO usage" "Consider disabling if indexing is not needed (balooctl disable)" "$current" "fix_baloo"

# 15. Load Average
load_avg=$(cut -d' ' -f1 /proc/loadavg)
cpu_count=$(nproc)
is_high=$(awk -v n1="$load_avg" -v n2="$cpu_count" 'BEGIN {if (n1 > n2) print 1; else print 0}')
if [ "$is_high" -eq 0 ]; then
    status="GOOD"
else
    status="WARNING"
fi
report "$status" "System Load" "Medium: CPU cores are saturated" "Identify high CPU processes (e.g., top or htop)" "$load_avg"

# 16. Power Supply Status
if [ -f "/sys/class/power_supply/ACAD/online" ]; then
    ac_status=$(cat /sys/class/power_supply/ACAD/online)
    if [ "$ac_status" -eq 1 ]; then
        status="GOOD"
        current="Plugged In"
    else
        status="WARNING"
        current="Battery Power"
    fi
    report "$status" "Power Supply" "Medium: Performance throttling likely on battery" "Plug in your Steam Deck for full performance" "$current"
fi

# 17. Trash Size
trash_size=$(du -ks "$HOME/.local/share/Trash" 2>/dev/null | awk '{print $1}')
trash_size_mb=$((trash_size / 1024))
if [ "$trash_size_mb" -gt 2048 ]; then
    status="WARNING"
else
    status="GOOD"
fi
report "$status" "Trash Size" "Low: Wasted disk space" "Empty your trash (Trash Size: ${trash_size_mb}MB)" "${trash_size_mb}MB" "fix_trash"

# 18. VS Code Extensions Count
ext_count=0
if [ -d "$HOME/.vscode/extensions" ]; then
    ext_count=$(find "$HOME/.vscode/extensions" -maxdepth 1 -mindepth 1 -type d | wc -l)
elif [ -d "$HOME/.var/app/com.visualstudio.code/data/vscode/extensions" ]; then
    ext_count=$(find "$HOME/.var/app/com.visualstudio.code/data/vscode/extensions" -maxdepth 1 -mindepth 1 -type d | wc -l)
elif command -v code >/dev/null 2>&1; then
    ext_count=$(timeout 5s code --list-extensions 2>/dev/null | wc -l)
fi
if [ "$ext_count" -gt 0 ]; then
    if [ "$ext_count" -gt 40 ]; then
        status="WARNING"
    else
        status="GOOD"
    fi
    report "$status" "VS Code Extensions" "Medium: High extension count can slow down editor" "Disable unused extensions" "$ext_count installed"
else
    report "GOOD" "VS Code Extensions" "None" "" "Unknown / None found"
fi

# 19. File Descriptors (ulimit)
ulimit_val=$(ulimit -n)
if [ "$ulimit_val" -lt 4096 ]; then
    status="WARNING"
else
    status="GOOD"
fi
report "$status" "File Descriptors (ulimit)" "High: 'Too many open files' crashes" "Run scripts/apply_opt_fixes.sh (requires reboot)" "$ulimit_val" "fix_ulimit"

# 20. SSD Trim Timer
if command -v systemctl >/dev/null 2>&1; then
    trim_status=$(systemctl is-enabled fstrim.timer 2>/dev/null || echo "inactive")
    if [ "$trim_status" == "enabled" ]; then
        status="GOOD"
    else
        status="WARNING"
    fi
    report "$status" "SSD Trim Timer" "Medium: degraded disk write speed over time" "Run: sudo systemctl enable --now fstrim.timer" "$trim_status" "fix_ssd_trim"
fi

# 21. Pacman Cache (Arch Linux specific)
if [ -d "/var/cache/pacman/pkg" ]; then
    pkg_cache_size=$(du -ks /var/cache/pacman/pkg 2>/dev/null | awk '{print $1}')
    pkg_cache_mb=$((pkg_cache_size / 1024))
    if [ "$pkg_cache_mb" -gt 4096 ]; then
        status="WARNING"
    else
        status="GOOD"
    fi
    report "$status" "Pacman Package Cache" "Low: Wasted Disk Space" "Run: sudo pacman -Sc" "${pkg_cache_mb}MB" "fix_pacman_cache"
fi

# 22. Failed System Services
if command -v systemctl >/dev/null 2>&1; then
    if failed_output=$(systemctl --failed --no-legend --plain 2>/dev/null); then
        failed_units=$(echo "$failed_output" | grep -c . || echo "0")
        failed_units=$(echo "$failed_units" | tr -d '[:space:]')
        if [ "$failed_units" -gt 0 ]; then
            status="WARNING"
            current="$failed_units failed"
        else
            status="GOOD"
            current="All running"
        fi
        report "$status" "System Services" "High: Potential system instability" "Run: systemctl --failed" "$current"
    else
         report "INFO" "System Services" "Unknown" "systemctl failed to run (container?)" "Skipped"
    fi
fi

# 23. Flatpak VS Code Permissions
if command -v flatpak >/dev/null 2>&1; then
    if flatpak list --app | grep -q "com.visualstudio.code"; then
        perms=$(flatpak info --show-permissions com.visualstudio.code 2>/dev/null | grep "filesystem")
        if [[ "$perms" == *"host"* ]] || [[ "$perms" == *"home"* ]]; then
             status="GOOD"
             current="Host/Home Access Enabled"
        else
             status="WARNING"
             current="Restricted"
        fi
        report "$status" "Flatpak Permissions" "High: Terminals and SDKs won't work" "Use Flatseal to grant 'All User Files' (filesystem=host) access" "$current" "fix_flatpak_perms"
    fi
fi

# 24. Heavy Development Processes (Memory Leaks)
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

# --- DISTROBOX CHECKS ---
echo -e "\n${BLUE}--- Distrobox Container Checks ($CONTAINER_NAME) ---${NC}"

if ! command -v distrobox >/dev/null 2>&1; then
    report "BAD" "Distrobox" "High" "Distrobox is not installed" "Install Distrobox" "Not Found"
else
    if ! distrobox list | grep -q "$CONTAINER_NAME"; then
        report "BAD" "Distrobox Container" "High" "Container '$CONTAINER_NAME' not found" "Run create-distrobox.sh" "Missing"
    else
        # 24. Java Environment
        java_check=$(distrobox enter "$CONTAINER_NAME" -- bash -c "java -version 2>&1 | head -n 1" || echo "Missing")
        if [[ "$java_check" == *"version"* ]] || [[ "$java_check" == *"runtime"* ]]; then
            status="GOOD"
        else
            status="BAD"
        fi
        report "$status" "Java Environment" "CRITICAL: Garmin Monkey C compiler requires Java" "Run: sudo apt install openjdk-17-jdk (inside container)" "$java_check" "fix_distrobox_libs"

        # 25. libusb
        libusb_check=$(distrobox enter "$CONTAINER_NAME" -- bash -c "dpkg -l | grep libusb-1.0-0 | awk '{print \$3}'" || echo "")
        if [ -n "$libusb_check" ]; then
            status="GOOD"
        else
            status="BAD"
        fi
        report "$status" "libusb-1.0-0" "HIGH: Simulator and Device communication will fail" "Run: sudo apt install libusb-1.0-0 (inside container)" "Missing" "fix_distrobox_libs"

        # 26. Simulator GUI Libs
        gui_libs_missing=""
        for lib in libgtk-3-0 libxtst6 libnss3 libasound2; do
            if ! distrobox enter "$CONTAINER_NAME" -- bash -c "dpkg -l | grep -q $lib"; then
                gui_libs_missing="$gui_libs_missing $lib"
            fi
        done
        if [ -z "$gui_libs_missing" ]; then
            status="GOOD"
        else
            status="BAD"
        fi
        report "$status" "Simulator GUI Libs" "CRITICAL: Garmin Simulator will fail to launch" "Run: sudo apt install$gui_libs_missing (inside container)" "Missing:$gui_libs_missing" "fix_distrobox_libs"
    fi
fi

# --- FINAL SUMMARY ---
echo
if [ "$FIX_APPLIED" = true ]; then
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}   FIXES APPLIED                                                      ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    if [ "$NEEDS_REBOOT" = true ]; then
        echo -e "${YELLOW}A system REBOOT is required for some fixes to take full effect.${NC}"
    else
        echo -e "You may need to restart VS Code or open a new terminal."
    fi
else
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}   DIAGNOSTIC COMPLETE (NO FIXES APPLIED)                           ${NC}"
    echo -e "${BLUE}======================================================================${NC}"
fi
echo