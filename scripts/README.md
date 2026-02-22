# Scripts README

This document explains the purpose of each script in this directory.

## Diagnostic and Optimization Scripts

### `diagnostic_and_fix.sh`

This is a comprehensive diagnostic and fix script for setting up a development environment on a Steam Deck, particularly for VS Code and Garmin SDK development within a Distrobox container.

It performs a wide range of checks, including:

-   **System Performance:** Swap usage, swappiness, inotify watches, VRAM allocation, CPU governor, disk space, I/O wait, thermal throttling, and more.
-   **VS Code Configuration:** Checks for Wayland flags, custom title bar, and GPU acceleration settings to improve performance and stability.
-   **Distrobox Container:** Verifies the existence of the specified container and checks for required libraries like Java, libusb, and GUI libraries for the Garmin simulator.
-   **General System Health:** Checks for large log files, Pacman cache, trash size, and failed system services.

For many of the issues it finds, the script offers to apply a fix automatically.

### `diagnostic.sh`

This script is a **read-only** version of `diagnostic_and_fix.sh`. It performs the same checks but **does not** offer to apply any fixes. It's useful for getting a report of the system's health without making any changes.

### `apply_opt_fixes.sh`

This is a simple wrapper script that executes `diagnostic_and_fix.sh`.

**Redundancy Note:** The three scripts `diagnostic_and_fix.sh`, `diagnostic.sh`, and `apply_opt_fixes.sh` are closely related.

-   `apply_opt_fixes.sh` is redundant if you run `diagnostic_and_fix.sh` directly. It exists as a convenience.
-   `diagnostic.sh` provides a subset of the functionality of `diagnostic_and_fix.sh` (the diagnostic part only).

You can think of them as:
-   `diagnostic.sh`: Just check for problems.
-   `diagnostic_and_fix.sh`: Check for problems and offer to fix them.
-   `apply_opt_fixes.sh`: A shortcut to run `diagnostic_and_fix.sh`.

---

## Distrobox Management Scripts

### `create-distrobox.sh`

This script creates a new `distrobox` container named `garmin-stable` using an Ubuntu 24.04 image by default. It also mounts the current workspace directory into the container at `/home/developer/host-workspace`.

This allows you to have a clean, isolated development environment without affecting your host system (SteamOS).

### `enter-distrobox.sh`

This is a helper script to easily enter the `garmin-stable` distrobox container. It also sets some environment variables to fix common GUI application issues when running them from within the container.

### `setup-in-distrobox.sh`

This script should be run **inside** the `garmin-stable` distrobox container. It installs a set of common development packages and tools, such as:

-   `build-essential`, `git`, `curl`, `wget`, `cmake`, `unzip`
-   `python3`, `python3-venv`, `python3-pip`
-   `libssl-dev`, `libusb-1.0-0`, `default-jre`
-   GTK modules to fix GUI application warnings.

This script prepares the container with the necessary dependencies for Garmin development.

---

## VS Code Management Scripts

### `install-vscode.sh`

This script installs Visual Studio Code. It automatically detects the underlying operating system and package manager:

-   On **SteamOS**, it installs VS Code via **Flatpak**.
-   On **Arch-based** systems, it uses `pacman`.
-   On **Debian/Ubuntu-based** systems, it adds the Microsoft repository and installs it using `apt`.
-   As a fallback, it will try to use `flatpak` if available.

### `install-extensions.sh`

This script reads a list of extension IDs from `extensions.txt` and installs them into VS Code using the `code` command-line interface.

---

## Garmin Development Scripts

### `update_garmin.sh`

This is a comprehensive update script that targets both the host system (your computer) and the `garmin-stable` distrobox container.

-   **On the host:** It detects your system's package manager (`pacman`, `apt`, `dnf`) and updates all system packages. It also updates all your `flatpak` applications. On SteamOS, it skips the system package update to avoid issues with the read-only filesystem.
-   **In the container:** It enters the `garmin-stable` container and runs `apt-get` to update all packages inside the isolated development environment.

The script provides a clear summary of all the updates it performed.

### `run-sdk-manager.sh`

This script launches the Garmin Connect IQ SDK Manager.

It's designed to work whether you run it from the host or from within the container. If you run it from the host, it will automatically use `distrobox` to launch the SDK manager from within the correct container. It also sets specific environment variables to prevent common GUI-related warnings and errors.

---

## Game Optimization Scripts (Diablo 2 Resurrected)

### `optimize_for_d2r.sh`

This is a powerful optimization script specifically designed to improve the performance and stability of Diablo 2: Resurrected on the Steam Deck. It performs a series of checks and applies fixes to free up system resources and configure the system for gaming.

Key optimizations include:

-   **Stopping Background Tasks:** Kills resource-heavy development processes like `distrobox`, `java`, `vscode`, and the Garmin `simulator`.
-   **Closing Launchers:** Terminates the Battle.net launcher to save CPU cycles.
-   **System Tuning:**
    -   Sets the CPU governor to `performance`.
    -   Reduces `swappiness` to prevent game stutter.
    -   Disables WiFi power management to reduce network latency.
-   **Cache Clearing:** Clears the D2R shader cache to resolve potential stuttering issues after game updates.
-   **System Checks:** Verifies that you have adequate VRAM (UMA) and Swap file size.

It can be run interactively in Desktop Mode or automatically in Game Mode (when used as a launch option).

### `launch_d2r_wrapper.sh`

This script is a wrapper for `optimize_for_d2r.sh`. Its main purpose is to launch the optimization script in a new terminal window so you can see its output. This is particularly useful when running it from the Steam UI in Desktop Mode.

When used as a launch option in Steam, it will first run the optimization script and then launch the game.

**Example Steam Launch Option:**

```
/path/to/launch_d2r_wrapper.sh %command%
```

---

## Utility Scripts

### `kill_sim_and_sleep.sh`

This is a simple utility script that does two things:

1.  **Forcefully kills the Garmin simulator process.** This is useful if the simulator has frozen or become unresponsive.
2.  **Suspends the Steam Deck.** This puts the device to sleep safely after ensuring the simulator is closed.

---

## Redundancies and Overlapping Scripts

Some of the scripts in this directory have overlapping functionality. This section clarifies the relationships between them.

-   **`diagnostic_and_fix.sh` vs `diagnostic.sh` vs `apply_opt_fixes.sh`**
    -   `diagnostic_and_fix.sh` is the main script that checks for issues and offers to fix them.
    -   `diagnostic.sh` is a **read-only** version that only reports issues.
    -   `apply_opt_fixes.sh` is a simple **wrapper** that just runs `diagnostic_and_fix.sh`. It's a convenience shortcut.

-   **`diagnostic_and_fix.sh` vs `optimize_for_d2r.sh`**
    -   These two scripts are very similar in structure, but they serve different purposes.
    -   `diagnostic_and_fix.sh` is for general development environment setup.
    -   `optimize_for_d2r.sh` is specifically for optimizing the system for playing Diablo 2: Resurrected. It does things that are beneficial for gaming but might not be desirable for a development workflow (like killing development tools).

-   **`launch_d2r_wrapper.sh` vs `optimize_for_d2r.sh`**
    -   `launch_d2r_wrapper.sh` is a **wrapper** for `optimize_for_d2r.sh`. Its main purpose is to launch the optimization script in a new terminal window, which is useful when running from the Steam UI in Desktop mode. It's also the recommended way to set up the launch options in Steam for D2R.
