#!/usr/bin/bash
# Wrapper to launch D2R optimization script in a terminal window
# This ensures output is visible and execution context is correct

# Save and unset LD_PRELOAD to prevent 32-bit/64-bit mismatch errors in script commands
if [[ -n "$LD_PRELOAD" ]]; then
    if [[ -z "$SAVED_LD_PRELOAD" ]]; then
        export SAVED_LD_PRELOAD="$LD_PRELOAD"
    fi
    unset LD_PRELOAD
fi

# Get absolute path to this script's directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TARGET_SCRIPT="$DIR/optimize_for_d2r.sh"
LOG="$HOME/Desktop/d2r_wrapper_debug.log"

echo "wrapper: Started at $(date)" > "$LOG"
echo "wrapper: Target script is '$TARGET_SCRIPT'" >> "$LOG"

# Make sure target is executable
chmod +x "$TARGET_SCRIPT"

# Function to launch terminal
launch_terminal() {
    # Check for Game Mode environment
    if [[ -n "$SteamDeck" || "$XDG_CURRENT_DESKTOP" == "gamescope" ]]; then
        echo "wrapper: Game Mode detected. Skipping terminal launch." >> "$LOG"
        return 1
    fi

    # Create a temporary script to ensure clean execution environment and proper argument passing
    TMP_SCRIPT="/tmp/run_d2r_opt_$(date +%s).sh"
    echo "#!/bin/bash" > "$TMP_SCRIPT"
    echo "\"$TARGET_SCRIPT\" --yes \"\$@\"" >> "$TMP_SCRIPT"
    echo "echo; read -p 'Press Enter to close...'" >> "$TMP_SCRIPT"
    chmod +x "$TMP_SCRIPT"

    # Method 1: konsole (KDE default)
    if command -v konsole &> /dev/null; then
        echo "wrapper: Launching via konsole" >> "$LOG"
        konsole -e "$TMP_SCRIPT" "$@" &
        return 0
    fi
    
    # Method 2: x-terminal-emulator (Generic)
    if command -v x-terminal-emulator &> /dev/null; then
        echo "wrapper: Launching via x-terminal-emulator" >> "$LOG"
        x-terminal-emulator -e "$TMP_SCRIPT" "$@" &
        return 0
    fi

    # Method 3: gnome-terminal
    if command -v gnome-terminal &> /dev/null; then
        echo "wrapper: Launching via gnome-terminal" >> "$LOG"
        gnome-terminal -- "$TMP_SCRIPT" "$@" &
        return 0
    fi
    
    # Method 4: xterm
    if command -v xterm &> /dev/null; then
        echo "wrapper: Launching via xterm" >> "$LOG"
        xterm -e "$TMP_SCRIPT" "$@" &
        return 0
    fi

    echo "wrapper: No terminal emulator found!" >> "$LOG"
    return 1
}

# Try to launch terminal
if launch_terminal "$@"; then
    echo "wrapper: Terminal launched successfully." >> "$LOG"
    exit 0
fi

# Fallback: Run directly if no terminal (e.g. Game Mode, or if in terminal already)
echo "wrapper: Running directly (fallback)" >> "$LOG"
"$TARGET_SCRIPT" --yes "$@" >> "$LOG" 2>&1
