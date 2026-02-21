#!/usr/bin/env bash
echo "Script accessed at $(date)" >> /tmp/d2r_debug_start.log
# ==============================================================================
# Diablo 2 Resurrected Optimization & Stability Tool for Steam Deck
# ==============================================================================

# --- Configuration ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine script directory reliably (even if symlinked or sourced)
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
LOG_FILE="$SCRIPT_DIR/d2r_optimize.log"
DESKTOP_LOG="$HOME/Desktop/d2r_optimize_debug.txt"

# Force log creation immediately to test write access
touch "$LOG_FILE" || LOG_FILE="/tmp/d2r_optimize_fallback.log"
chmod 666 "$LOG_FILE" 2>/dev/null
echo "Starting D2R Optimization Script at $(date)" > "$DESKTOP_LOG"

# Redirect all stdout and stderr to the log file for debugging (append mode)
exec > >(tee -a "$LOG_FILE" | tee -a "$DESKTOP_LOG") 2>&1

echo "==================================================="
echo "Run started at: $(date)"
echo "Script Path: $0"
echo "Working Dir: $(pwd)"
echo "User: $(whoami)"
echo "Args: $@"

D2R_APP_ID="2536520" # Infernal Edition
FIX_APPLIED=false
AUTO_FIX=false

# Check for --yes or -y flag
if [[ "$1" == "--yes" || "$1" == "-y" ]]; then
    AUTO_FIX=true
    shift # Remove the flag so we can execute potential commands later
fi

# Auto-detect Game Mode and force AUTO_FIX
# If running in gamescope (Game Mode), always auto-fix regardless of arguments
# This allows the script to be used as a launch option: ./script.sh %command%
if [[ -n "$SteamDeck" || "$XDG_CURRENT_DESKTOP" == "gamescope" ]]; then
     AUTO_FIX=true
fi

# --- Helper Functions ---

ask_confirm() {
    if [[ "$AUTO_FIX" == "true" ]]; then
        return 0
    fi

    # Game Mode Detection (even with TTY)
    if [[ -n "$SteamDeck" || "$XDG_CURRENT_DESKTOP" == "gamescope" ]]; then
        echo -e "${YELLOW}Game Mode detected.${NC} Auto-confirming in 3s..."
        if read -t 3 -p "$1 [Y/n] " yn; then
            case $yn in
                [Nn]* ) return 1;;
                * ) return 0;;
            esac
        else
            echo " Auto-confirmed."
            return 0
        fi
    fi

    if [[ ! -t 0 ]]; then
        # Try to detect Game Mode environment variables (redundant but safe fallback)
        if [[ -n "$SteamDeck" || "$XDG_CURRENT_DESKTOP" == "gamescope" ]]; then
             echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Game Mode detected without TTY. Assuming --yes." >> "$LOG_FILE"
             return 0 # Auto-confirm in Game Mode if not interactive
        fi

        echo -e "         ${YELLOW}Warning:${NC} No interactive terminal detected (likely Game Mode or script redirect)."
        echo -e "         Use the ${BLUE}--yes${NC} or ${BLUE}-y${NC} flag to apply optimizations automatically."
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] No TTY available for prompt: $1" >> "$LOG_FILE"
        return 1
    fi

    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
            [Yy]* ) return 0;; 
            [Nn]* ) return 1;; 
            * ) return 1;; 
        esac
    done
}

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

    # Log to file (plain text)
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$status] $name: $current" >> "$LOG_FILE"

    if [[ -n "$fix_function" && "$status" != "GOOD" ]]; then
        if ask_confirm "       -> Apply optimization for '$name'?"; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ACTION] Applying fix: $fix_function for $name" >> "$LOG_FILE"
            "$fix_function"
            FIX_APPLIED=true
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ACTION] User skipped fix for $name" >> "$LOG_FILE"
            echo -e "       -> Skipped."
        fi
    fi
    echo "----------------------------------------------------------------------"
}

# --- Fix Functions ---

fix_stop_dev_tasks() {
    echo -e "         Stopping all Distrobox containers..."
    # Timeout after 15s to avoid hang
    if ! timeout 15s distrobox stop --all --yes 2>/dev/null; then
         echo -e "         ${YELLOW}Warning:${NC} Distrobox stop timed out or failed. Continuing..."
         echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] Distrobox stop timed out." >> "$LOG_FILE"
    fi
    echo -e "         Killing memory-heavy development processes..."
    pkill -9 -x "simulator" 2>/dev/null
    pkill -9 -x "java" 2>/dev/null
    pkill -9 -x "node" 2>/dev/null
    # Kill VS Code (safer matching than -f)
    # pkill -9 -x "code" 2>/dev/null
    # pkill -9 -x "code-oss" 2>/dev/null
    # pkill -9 -x "visual-studio-code" 2>/dev/null
    # pkill -9 -f "com.visualstudio.code" 2>/dev/null
    
    sleep 1
    local remaining=$(pgrep -x "code" | wc -l)
    if [ "$remaining" -eq 0 ]; then
        echo -e "         All development tasks stopped."
    else
        echo -e "         ${YELLOW}Note:${NC} Some VS Code processes ($remaining) are still active."
    fi
}

fix_kill_bnet() {
    echo -e "         Closing Battle.net Launcher..."
    pkill -9 "Battle.net.exe" 2>/dev/null
    pkill -9 "Agent.exe" 2>/dev/null
}

fix_cpu_governor() {
    echo -e "         Setting CPU Governor to Performance..."
    # Use non-interactive sudo if possible to avoid hang
    if echo "performance" | sudo -n tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1; then
        :
    else
         echo -e "         ${YELLOW}Warning:${NC} Sudo requires password or failed. Skipping CPU Governor fix."
         echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] Sudo failed for CPU governor." >> "$LOG_FILE"
         return 1
    fi
}

fix_swappiness() {
    echo -e "         Reducing swappiness to 1 (recommmended for D2R)..."
    if echo "vm.swappiness=1" | sudo -n tee /etc/sysctl.d/99-d2r-perf.conf > /dev/null 2>&1; then
        sudo -n sysctl vm.swappiness=1 > /dev/null 2>&1
    else
         echo -e "         ${YELLOW}Warning:${NC} Sudo requires password or failed. Skipping swappiness fix."
         echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] Sudo failed for swappiness." >> "$LOG_FILE"
         return 1
    fi
}

fix_clear_shaders() {
    if pgrep -x "steam" > /dev/null; then
        echo -e "         ${YELLOW}Warning:${NC} Steam is currently running."
        echo -e "         It is highly recommended to close Steam before clearing shader caches."
        if ! ask_confirm "         Continue anyway?"; then
            echo "         Aborted shader cache clearing."
            return 0
        fi
    fi

    local shader_base="$HOME/.local/share/Steam/steamapps/shadercache"
    local d2r_shader_path="$shader_base/$D2R_APP_ID"

    if [ -d "$d2r_shader_path" ]; then
        echo -e "         Targeting D2R specific shader cache (App ID: $D2R_APP_ID)..."
        rm -rf "$d2r_shader_path" 2>/dev/null
        echo -e "         Cleared D2R shader cache."
    elif [ -d "$shader_base" ]; then
        echo -e "         D2R-specific folder not found. Cleaning entire shader cache..."
        echo -e "         ${YELLOW}Note:${NC} This will affect all games."
        rm -rf "$shader_base"/* 2>/dev/null
        echo -e "         Cleared entire Steam shader cache folder."
    else
        echo -e "         Shader cache folder not found."
    fi
}

fix_wifi_power_mgmt() {
    echo -e "         Disabling WiFi Power Management for low latency..."
    
    # Identify interface
    local iface=""
    if [ -d "/sys/class/net/wlan0" ]; then
        iface="wlan0"
    else
        iface=$(ls /sys/class/net/ | grep -E '^wlan|^wlp' | head -n 1)
    fi

    if [ -z "$iface" ]; then
        echo -e "         ${YELLOW}Warning:${NC} No WiFi interface found."
        return 1
    fi

    # Try runtime fix using iw (preferred if installed)
    if command -v iw &> /dev/null; then
        # Try non-interactive first, then interactive if not in auto mode
        if sudo -n iw dev "$iface" set power_save off > /dev/null 2>&1; then
             echo -e "         Runtime power management disabled (via iw)."
        elif [[ "$AUTO_FIX" != "true" ]] && sudo iw dev "$iface" set power_save off; then
             echo -e "         Runtime power management disabled (via iw)."
        else
            echo -e "         ${YELLOW}Warning:${NC} Failed to set runtime power management via iw (sudo required)."
        fi
    else
        # Fallback: sysfs power control
        # Note: 'on' means power management is ALWAYS ON (active), i.e., NO SLEEP. 'auto' means sleep allowed.
        if echo "on" | sudo -n tee "/sys/class/net/$iface/power/control" > /dev/null 2>&1; then
            echo -e "         Runtime power management disabled (via sysfs)."
        elif [[ "$AUTO_FIX" != "true" ]]; then
             # Interactive fallback
             if echo "on" | sudo tee "/sys/class/net/$iface/power/control" > /dev/null; then
                 echo -e "         Runtime power management disabled (via sysfs)."
             else
                 echo -e "         ${YELLOW}Warning:${NC} Failed to set runtime power management via sysfs."
             fi
        else
             echo -e "         ${YELLOW}Warning:${NC} Failed to set runtime power management via sysfs."
        fi
    fi

    # Try permanent fix via NetworkManager config
    # Ensure directory exists first
    if sudo -n mkdir -p /etc/NetworkManager/conf.d > /dev/null 2>&1; then
        # 2 = disable power save
        if echo -e "[connection]\nwifi.powersave=2" | sudo -n tee /etc/NetworkManager/conf.d/disable-wifi-powersave.conf > /dev/null 2>&1; then
            echo -e "         Permanent configuration created."
        else
            echo -e "         ${YELLOW}Warning:${NC} Failed to create permanent config file."
        fi
    else
        echo -e "         ${YELLOW}Warning:${NC} Failed to create config directory (sudo required or read-only filesystem)."
    fi
}

# --- Diagnostic Checks ---

check_wifi_power_mgmt() {
    # 1. Identify WiFi Interface
    local iface=""
    if [ -d "/sys/class/net/wlan0" ]; then
        iface="wlan0"
    else
        iface=$(ls /sys/class/net/ | grep -E '^wlan|^wlp' | head -n 1)
    fi

    if [ -z "$iface" ]; then
         report "INFO" "WiFi Power Management" \
            "No WiFi interface found (checked wlan0, wlp*)." \
            "Cannot optimize WiFi." \
            "None"
         return
    fi

    # 2. Check Status (Try iw first, then sysfs)
    local ps_status="Unknown"
    local raw_status=""
    
    if command -v iw &> /dev/null; then
        raw_status=$(iw dev "$iface" get power_save 2>/dev/null | awk '{print $3}')
        if [[ "$raw_status" == "on" ]]; then ps_status="On"; fi
        if [[ "$raw_status" == "off" ]]; then ps_status="Off"; fi
    fi
    
    # Fallback to sysfs if iw failed or missing
    if [[ "$ps_status" == "Unknown" ]]; then
        if [ -f "/sys/class/net/$iface/power/control" ]; then
            raw_status=$(cat "/sys/class/net/$iface/power/control")
            if [[ "$raw_status" == "auto" ]]; then ps_status="On (Auto)"; fi
            if [[ "$raw_status" == "on" ]]; then ps_status="Off"; fi
        fi
    fi
    
    # 3. Report
    if [[ "$ps_status" == "On" || "$ps_status" == "On (Auto)" ]]; then
        report "WARNING" "WiFi Power Management" \
            "Power saving ($ps_status) increases ping spikes/latency." \
            "Disable WiFi power management." \
            "$ps_status" \
            "fix_wifi_power_mgmt"
    elif [[ "$ps_status" == "Off" ]]; then
        report "GOOD" "WiFi Power Management" \
            "" \
            "" \
            "Off (Low Latency)"
    else
        # If still unknown, assume bad if config file doesn't exist
        if [ ! -f "/etc/NetworkManager/conf.d/disable-wifi-powersave.conf" ]; then
             report "WARNING" "WiFi Power Management" \
                "Status unknown, but optimization likely missing." \
                "Force disable power management to be safe." \
                "Unknown" \
                "fix_wifi_power_mgmt"
        else
             report "GOOD" "WiFi Power Management" "" "" "Unknown (Config Present)"
        fi
    fi
}

check_background_tasks() {
    # Use timeout to prevent hanging if distrobox is unresponsive
    local running_containers=$(timeout 5s distrobox list 2>/dev/null | grep "running" | wc -l)
    if [ $? -ne 0 ]; then
        # If timeout or error, assume 0 running or handle error gracefully
        running_containers=0
    fi
    local java_procs=$(pgrep -x "java" | wc -l)
    local sim_procs=$(pgrep -x "simulator" | wc -l)
    local code_procs=$(pgrep -x "code" | wc -l)
    local bnet_procs=$(pgrep -f "Battle.net.exe" | wc -l)
    
    if [ "$running_containers" -gt 0 ] || [ "$java_procs" -gt 0 ] || [ "$sim_procs" -gt 0 ] || [ "$code_procs" -gt 0 ]; then
        report "BAD" "Background Dev Tasks" \
            "Heavy tasks steal CPU cycles and cause frame stutters in D2R." \
            "Stop all containers, VS Code, and kill java/simulator processes." \
            "$running_containers containers, $java_procs java, $sim_procs sim, $code_procs VS Code" \
            "fix_stop_dev_tasks"
    else
        report "GOOD" "Background Dev Tasks" "" "" "None found"
    fi

    if [ "$bnet_procs" -gt 0 ]; then
        report "WARNING" "Battle.net Launcher" \
            "The launcher consumes CPU while the game is running." \
            "Kill the launcher once the game is launched (or set it to close on game launch in Bnet settings)." \
            "$bnet_procs processes" \
            "fix_kill_bnet"
    fi
}

check_cpu_governor() {
    local gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    if [ "$gov" != "performance" ]; then
        report "WARNING" "CPU Scaling Governor" \
            "Powersave can lead to variable clock speeds and stuttering." \
            "Switch to 'performance' governor for stable gaming." \
            "$gov" \
            "fix_cpu_governor"
    else
        report "GOOD" "CPU Scaling Governor" "" "" "performance"
    fi
}

check_uma_vram() {
    local vram_total=$(cat /sys/class/drm/card0/device/mem_info_vram_total)
    local vram_gb=$((vram_total / 1024 / 1024 / 1024))
    
    if [ "$vram_gb" -lt 3 ]; then
        report "BAD" "UMA Framebuffer (VRAM)" \
            "D2R has VRAM leaks. 1GB is insufficient and leads to crashes." \
            "Change UMA Framebuffer to 4GB in Steam Deck BIOS (Settings -> Home -> Advanced)." \
            "${vram_gb}GB"
    else
        report "GOOD" "UMA Framebuffer (VRAM)" "" "" "${vram_gb}GB"
    fi
}

check_swap_settings() {
    local swappiness=$(cat /proc/sys/vm/swappiness)
    local swap_total=$(free -g | grep "Swap" | awk '{print $2}')

    if [ "$swappiness" -gt 10 ]; then
        report "WARNING" "Swappiness" \
            "Default swappiness (100) causes stutters as game data is cached to disk." \
            "Set swappiness to 1." \
            "$swappiness" \
            "fix_swappiness"
    else
        report "GOOD" "Swappiness" "" "" "$swappiness"
    fi

    if [ "$swap_total" -lt 15 ]; then
        report "WARNING" "Swap File Size" \
            "8GB or less can cause OOM crashes in D2R/Battle.net." \
            "Increase swap to 16GB (requires manual setup or CryoUtilities)." \
            "${swap_total}GB"
    else
        report "GOOD" "Swap File Size" "" "" "${swap_total}GB"
    fi
}

check_shader_cache() {
    local shader_base="$HOME/.local/share/Steam/steamapps/shadercache"
    local d2r_shader_path="$shader_base/$D2R_APP_ID"
    
    if [ -d "$d2r_shader_path" ]; then
        local size=$(du -sh "$d2r_shader_path" | awk '{print $1}')
        # In Auto-Fix mode (Game Mode launch), only clear if size is very large (e.g. > 500M) or user explicitly accepts
        # Otherwise we report GOOD to avoid clearing every launch
        if [[ "$AUTO_FIX" == "true" && $(du -s "$d2r_shader_path" | awk '{print $1}') -lt 512000 ]]; then
             report "GOOD" "Infernal Shader Cache" "" "" "$size (Auto-kept)"
        else
             report "INFO" "Infernal Shader Cache" \
                "Accumulated shaders can sometimes cause stutters after game updates." \
                "Clear D2R shaders to force a rebuild." \
                "$size" \
                "fix_clear_shaders"
        fi
    elif [ -d "$shader_base" ]; then

        local size=$(du -sh "$shader_base" | awk '{print $1}')
        report "INFO" "Steam Shader Cache (Global)" \
            "D2R-specific cache not found (likely non-Steam or first run). Global cache available." \
            "Clear all shaders to force a rebuild." \
            "$size" \
            "fix_clear_shaders"
    fi
}

# --- Execution ---

echo "---------------------------------------------------" >> "$LOG_FILE"
echo "Run started at: $(date)" >> "$LOG_FILE"

clear
echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}   Diablo 2 Resurrected Optimization & Stability Tool               ${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo ""

if [[ "$AUTO_FIX" == "true" ]]; then
    # Game Mode / Auto-Fix Logic
    echo -e "${YELLOW}Auto-Fix enabled (--yes). All safe optimizations will be applied automatically.${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Auto-Fix Mode Enabled" >> "$LOG_FILE"
    echo ""
    
    # Run critical fixes first (game mode priority)
    fix_stop_dev_tasks
    fix_cpu_governor
    # Run Wi-Fi fix immediately without check if runtime allows
    fix_wifi_power_mgmt
    
    # Diagnostic checks still run to report/fix others

    check_background_tasks # Double check
    check_cpu_governor # Double check
    check_uma_vram
    check_swap_settings
    check_wifi_power_mgmt
    check_shader_cache

    # If arguments are passed (e.g. from Steam Launch Options %command%), execute them now
    # Check if there are arguments AND they are not empty string (sometimes wrapper issues)
    if [[ $# -gt 0 && -n "$1" ]]; then
        echo -e "${GREEN}Launching Game Command (from args): $@${NC}"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Launching game command: $@" >> "$LOG_FILE"
        exec "$@"
    else
        # Try to read game path from config file
        CONFIG_FILE="$SCRIPT_DIR/d2r_path.cfg"
        if [[ -f "$CONFIG_FILE" ]]; then
            # Read first valid line (skipping comments and empty lines)
            GAME_PATH=$(grep -vE '^\s*#|^\s*$' "$CONFIG_FILE" | head -n 1)
            if [[ -n "$GAME_PATH" && -f "$GAME_PATH" ]]; then
                echo -e "${GREEN}Found configured game path: $GAME_PATH${NC}"
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] Auto-launching configured game: $GAME_PATH" >> "$LOG_FILE"
                
                # Check if running in Wine/Proton environment
                if command -v wine &> /dev/null; then
                     exec wine "$GAME_PATH"
                else
                     echo -e "${YELLOW}Warning: 'wine' command not found. Trying direct execution...${NC}"
                     exec "$GAME_PATH"
                fi
                exit 0
            fi
        fi

        echo -e "${RED}ERROR: No game command provided and no valid path in d2r_path.cfg!${NC}"
        echo -e "If you added this script as a Non-Steam Game, do ONE of the following:"
        echo -e "1. Edit Steam Launch Options: Add ${YELLOW}\"/path/to/game.exe\"${NC} as an argument."
        echo -e "2. Edit ${YELLOW}$CONFIG_FILE${NC} and add the full path to your game executable."
        echo -e ""
        echo -e "Closing in 15 seconds..."
        sleep 15
        exit 1
    fi
else
    # Desktop Mode (Interactive)
    echo -e "Use the ${BLUE}--yes${NC} flag to skip prompts and run automatically (for Game Mode)."
    
    check_background_tasks
    check_cpu_governor
    check_uma_vram
    check_swap_settings
    check_wifi_power_mgmt
    check_shader_cache
fi

echo ""
if [ "$FIX_APPLIED" = true ]; then
    echo -e "${GREEN}Optimizations applied successfully.${NC}"
else
    echo -e "No changes were made."
fi
echo -e "Launch D2R using ${YELLOW}GE-Proton${NC} for best results."
echo -e "  (Reason: Fixes shader stuttering, memory leaks, and Battle.net launcher issues better than standard Proton)"
echo "" 

