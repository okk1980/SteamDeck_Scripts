#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="garmin-stable"
SUMMARY_LOG=""

add_summary() {
    SUMMARY_LOG="${SUMMARY_LOG}- $1\n"
}

add_update_summary() {
    local manager_output="$1"
    if [ -n "$manager_output" ]; then
        SUMMARY_LOG="${SUMMARY_LOG}$manager_output\n"
    fi
}

echo "=========================================="
echo "   GARMIN DEV: HOST & CONTAINER UPDATE    "
echo "=========================================="

# Keep sudo credentials alive (best effort)
IS_STEAMOS=false
IS_CONTAINER=false

if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
    IS_CONTAINER=true
fi

if [ -f /etc/os-release ] && grep -q "ID=steamos" /etc/os-release; then
    IS_STEAMOS=true
fi

if [ "$IS_CONTAINER" = true ]; then
    echo ">> [Container] Ausführung innerhalb eines Containers erkannt."
    echo "   -> Starte Container-Upgrade (apt)..."
    updates=$(apt-get --just-print upgrade | awk -F '[/ ]' '/^  Inst/ {print "    - " $2 " -> " $4}')
    if sudo apt-get update -qq && \
       sudo apt-get install -y -qq libcanberra-gtk-module libcanberra-gtk3-module > /dev/null 2>&1 && \
       sudo apt-get dist-upgrade -y -qq && \
       sudo apt-get autoremove -y -qq && \
       sudo apt-get clean; then
        if [ -n "$updates" ]; then
            add_summary "Container-Pakete: Alle Updates erfolgreich installiert."
            add_update_summary "$updates"
        else
            add_summary "Container-Pakete: Keine Updates verfügbar."
        fi
    else
        add_summary "⚠️ Container-Pakete: Fehler beim Update (apt)."
    fi

    echo "=========================================="
    echo "       ZUSAMMENFASSUNG (CONTAINER)        "
    echo "=========================================="
    printf "%b" "${SUMMARY_LOG}"
    echo "=========================================="
    exit 0
fi

if command -v sudo > /dev/null 2>&1; then
    if [ "$IS_STEAMOS" = true ]; then
        echo ">> [Host] SteamOS erkannt. Prüfe Sudo-Verfügbarkeit..."
    fi
    sudo -v || echo ">> [Host] Sudo fehlgeschlagen oder Passwort erforderlich."
    # keep sudo timestamp alive in background (use $$ for current shell pid)
    ( 
        while true; do 
            sudo -n true 2>/dev/null || true
            sleep 60
            # Kill this loop if the parent script is no longer running
            if ! kill -0 "$$" 2>/dev/null; then
                exit
            fi
        done 
    ) &
    SUDO_LOOP_PID=$!
    trap 'kill $SUDO_LOOP_PID 2>/dev/null || true' EXIT
fi

echo ">> [Host] Update: Paketmanager, Flatpaks und Distrobox prüfen..."

# Check distrobox presence
if command -v distrobox > /dev/null 2>&1; then
    echo ">> [Host] Distrobox gefunden."
else
    echo ">> [Host] Distrobox nicht gefunden. Container-Teil wird übersprungen."
fi

# Host package manager updates (Arch/apt/dnf)
if [ "$IS_STEAMOS" = true ]; then
    echo ">> [Host] SteamOS erkannt: Überspringe pacman System-Upgrade (Read-only FS)."
    add_summary "Host OS: SteamOS (System-Upgrade übersprungen)"
elif command -v pacman > /dev/null 2>&1; then
    echo ">> [Host] pacman (Arch) erkannt: System-Upgrade läuft..."
    updates=$(pacman -Qu --color=never | sed 's/ -> / -> /;s/^/    - /')
    if sudo pacman -Syu --noconfirm -q > /dev/null 2>&1; then
        if [ -n "$updates" ]; then
            add_summary "Host-Pakete (pacman): System aktuell."
            add_update_summary "$updates"
        else
            add_summary "Host-Pakete (pacman): Keine Updates verfügbar."
        fi
    else
        add_summary "⚠️ Host-Pakete (pacman): Fehler beim Update."
    fi
elif command -v apt-get > /dev/null 2>&1; then
    echo ">> [Host] apt erkannt: System-Upgrade läuft..."
    updates=$(apt-get --just-print upgrade | awk -F '[/ ]' '/^  Inst/ {print "    - " $2 " -> " $4}')
    if sudo apt-get update -qq && sudo apt-get full-upgrade -y -qq; then
        if [ -n "$updates" ]; then
            add_summary "Host-Pakete (apt): System aktuell."
            add_update_summary "$updates"
        else
            add_summary "Host-Pakete (apt): Keine Updates verfügbar."
        fi
    else
        add_summary "⚠️ Host-Pakete (apt): Fehler beim Update."
    fi
elif command -v dnf > /dev/null 2>&1; then
    echo ">> [Host] dnf erkannt: System-Upgrade läuft..."
    updates=$(dnf list upgrades | tail -n +2 | awk '{print "    - " $1 " " $2}')
    if sudo dnf upgrade -y -q; then
        if [ -n "$updates" ]; then
            add_summary "Host-Pakete (dnf): System aktuell."
            add_update_summary "$updates"
        else
            add_summary "Host-Pakete (dnf): Keine Updates verfügbar."
        fi
    else
        add_summary "⚠️ Host-Pakete (dnf): Fehler beim Update."
    fi
else
    echo ">> [Host] Kein bekannter Paketmanager gefunden. Überspringe Host-Paket-Upgrade."
    add_summary "Host-Pakete: Kein unterstützter Paketmanager gefunden."
fi

# Flatpak updates
if command -v flatpak > /dev/null 2>&1; then
    echo ">> [Host] Aktualisiere Flatpaks..."
    updates=$(flatpak remote-ls --updates --columns=application,name | awk -F '\t' 'NR>1 {print "    - " $2 " (" $1 ")"}' | sort)
    if [ -n "$updates" ]; then
        if flatpak update -y; then
            add_summary "Flatpaks: Updates installiert."
            add_update_summary "$updates"
        else
            add_summary "⚠️ Flatpaks: Fehler beim Update."
        fi
    else
        add_summary "Flatpaks: Keine Updates verfügbar."
        flatpak update -y > /dev/null 2>&1
    fi
fi

echo ""
echo ">> [Container] Prüfe ob Container '$CONTAINER_NAME' existiert..."

if command -v distrobox > /dev/null 2>&1 && distrobox list 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
    echo ">> [Container] Betrete '$CONTAINER_NAME' und führe Wartung aus..."

    # First update the apt cache so we can see what updates are available
    distrobox enter "$CONTAINER_NAME" -- sudo apt-get update -qq

    # Now calculate the updates based on the fresh cache
    updates=$(distrobox enter "$CONTAINER_NAME" -- apt-get --just-print upgrade | awk -F '[/ ]' '/^  Inst/ {print "    - " $2 " -> " $4}')
    
    # Perform the actual upgrade
    if distrobox enter "$CONTAINER_NAME" -- bash -lc "
        set -euo pipefail
        echo '   -> Starte Container-Upgrade (apt)...'
        # apt-get update already ran above, but running it again is harmless or we can skip it
        sudo apt-get dist-upgrade -y -qq
        sudo apt-get autoremove -y -qq
        sudo apt-get clean
    "; then
        if [ -n "$updates" ]; then
            add_summary "Distrobox ($CONTAINER_NAME): Updates installiert."
            add_update_summary "$updates"
        else
            add_summary "Distrobox ($CONTAINER_NAME): Keine Updates verfügbar."
        fi
    else
        add_summary "⚠️ Distrobox ($CONTAINER_NAME): Fehler beim Update."
    fi
else
    echo ">> [Container] Container '$CONTAINER_NAME' nicht gefunden — überspringe Container-Update."
    add_summary "Distrobox: Container '$CONTAINER_NAME' nicht gefunden."
fi

echo ""
echo "=========================================="
echo "         WARTUNGS-ZUSAMMENFASSUNG         "
echo "=========================================="
printf "%b" "${SUMMARY_LOG}"
echo "=========================================="
echo "✅ ALLE VORGÄNGE ABGESCHLOSSEN"
echo "=========================================="

# Check if we are running in Steam Game Mode (where no terminal is visible)
# Steam Game Mode typically has SteamGameId or other environment variables, 
# or we can check if we are attached to a TTY.
if [ -t 0 ]; then
    read -p "Drücke ENTER zum Schließen..." || true
else
    echo "Kein Terminal erkannt. Schließe in 5 Sekunden..."
    sleep 5
fi
