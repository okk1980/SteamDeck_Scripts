#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="garmin-stable"

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
    echo "   -> Starte Container-Upgrade (apt)"
    sudo apt-get update
    # Install commonly missing GTK modules for UI apps (sdkmanager, simulator)
    sudo apt-get install -y libcanberra-gtk-module libcanberra-gtk3-module
    sudo apt-get dist-upgrade -y
    sudo apt-get autoremove -y
    sudo apt-get clean
    echo "=========================================="
    echo "✅ CONTAINER-WARTUNG ERFOLGREICH BEENDET"
    echo "=========================================="
    exit 0
fi

if command -v sudo > /dev/null 2>&1; then
    if [ "$IS_STEAMOS" = true ]; then
        echo ">> [Host] SteamOS erkannt. Prüfe Sudo-Verfügbarkeit..."
    fi
    sudo -v || echo ">> [Host] Sudo fehlgeschlagen oder Passwort erforderlich."
    # keep sudo timestamp alive in background (use $$ for current shell pid)
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" >/dev/null 2>&1 || exit; done ) 2>/dev/null &
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
elif command -v pacman > /dev/null 2>&1; then
    echo ">> [Host] pacman (Arch) detected: full system upgrade..."
    sudo pacman -Syu --noconfirm || echo "pacman update had issues; please check manually"
elif command -v apt-get > /dev/null 2>&1; then
    echo ">> [Host] apt detected: update + full-upgrade..."
    sudo apt-get update && sudo apt-get full-upgrade -y || echo "apt upgrade had issues; please check"
elif command -v dnf > /dev/null 2>&1; then
    echo ">> [Host] dnf detected: upgrade..."
    sudo dnf upgrade -y || echo "dnf upgrade had issues; please check"
else
    echo ">> [Host] Kein bekannter Paketmanager gefunden. Überspringe Host-Paket-Upgrade."
fi

# Flatpak updates
if command -v flatpak > /dev/null 2>&1; then
    echo ">> [Host] Aktualisiere Flatpaks..."
    flatpak update -y || echo "flatpak update failed"
fi

echo ""
echo ">> [Container] Prüfe ob Container '$CONTAINER_NAME' existiert..."

if command -v distrobox > /dev/null 2>&1 && distrobox list 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
    echo ">> [Container] Betrete '$CONTAINER_NAME' und führe Wartung aus..."

    distrobox enter "$CONTAINER_NAME" -- bash -lc "
        set -euo pipefail
        echo '   -> Starte Container-Upgrade (apt)'

        # Führe apt update & Full upgrade im Container durch
        sudo apt-get update
        sudo apt-get dist-upgrade -y
        sudo apt-get autoremove -y
        sudo apt-get clean

        echo '      -> Container Update abgeschlossen.'
    "
else
    echo ">> [Container] Container '$CONTAINER_NAME' nicht gefunden — überspringe Container-Update."
fi

echo "=========================================="
echo "✅ WARTUNG ERFOLGREICH BEENDET"
echo "=========================================="
read -p "Drücke ENTER zum Schließen..." || true
