#!/usr/bin/env bash
set -eu

echo "Detecting package manager and attempting to install Visual Studio Code (or Flatpak package)."

# Detect SteamOS
IS_STEAMOS=false
if [ -f /etc/os-release ] && grep -q "ID=steamos" /etc/os-release; then
  IS_STEAMOS=true
fi

if [ "$IS_STEAMOS" = true ]; then
  echo "Detected SteamOS. Promoting Flatpak installation for the host."
  flatpak install -y flathub com.visualstudio.code || echo "Flatpak install failed; check if flathub is enabled."
elif command -v pacman > /dev/null 2>&1; then
  echo "Detected pacman (Arch-based). Trying to install 'code' package via pacman."
  sudo pacman -Sy --noconfirm code || echo "Could not install 'code' via pacman; consider AUR or Flatpak."
elif command -v apt >/dev/null 2>&1; then
  echo "Detected apt (Debian/Ubuntu). Installing VS Code from Microsoft repository."
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmour >/tmp/microsoft.gpg || true
  if [ -f /tmp/microsoft.gpg ]; then
    sudo install -o root -g root -m 644 /tmp/microsoft.gpg /etc/apt/trusted.gpg.d/ || true
    rm -f /tmp/microsoft.gpg
  fi
  sudo sh -c 'echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
  sudo apt update
  sudo apt install -y code || echo "Failed to install 'code' via apt; try Flatpak or manual install."
elif command -v flatpak >/dev/null 2>&1; then
  echo "Installing Visual Studio Code via Flatpak from Flathub."
  flatpak install -y flathub com.visualstudio.code || echo "Flatpak install failed; please run manually."
else
  echo "No supported package manager detected. Please install VS Code manually (https://code.visualstudio.com/)."
fi

echo "Installation script finished. If you installed successfully, ensure the 'code' CLI is on your PATH."