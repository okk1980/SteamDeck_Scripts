# replace USERNAME with your GitHub username
gh repo create okk1980/SteamDeck_Scripts --public --source=. --remote=origin --push# SteamDeck_Scripts

Repository of scripts and VS Code workspace settings to make coding on a Steam Deck (or other Linux handheld) easier.

Quick steps

1. Create a persistent development container (distrobox named `garmin-stable`) and mount this workspace into it. See the `scripts/create-distrobox.sh` helper.

```bash
# create and mount this workspace into the distrobox
bash scripts/create-distrobox.sh

# enter the distrobox
bash scripts/enter-distrobox.sh
```

2. Inside the distrobox, run the installer scripts (they operate inside the container so changes persist in the container's filesystem):

```bash
# from inside the distrobox (or use the provided setup script)
bash scripts/setup-in-distrobox.sh
bash scripts/install-extensions.sh
```

Files added

- `scripts/install-vscode.sh` — detects package manager and installs VS Code or Flatpak.
- `scripts/install-extensions.sh` — installs extensions listed in `extensions.txt`.
- `extensions.txt` — recommended extension IDs.
- `dotfiles/vscode-settings.json` — opinionated settings tuned for a handheld screen and controller usage.
- `.vscode/steamdeck.code-workspace` — workspace file referencing the folder.
- `scripts/create-distrobox.sh` — creates a distrobox named `garmin-stable` and mounts this workspace into it.
- `scripts/enter-distrobox.sh` — helper to enter the `garmin-stable` distrobox.
- `scripts/setup-in-distrobox.sh` — installs common dev packages inside the distrobox.
- `scripts/diagnostic.sh` — diagnostic tool to check Steam Deck and Container performance settings.

Next steps

- Run the scripts above.
- Review `dotfiles/vscode-settings.json` and adapt to your preferences.
- Optionally commit this folder to a dotfiles repo.
