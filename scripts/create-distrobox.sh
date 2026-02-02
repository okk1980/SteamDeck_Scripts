#!/usr/bin/env bash
set -euo pipefail

# Creates a distrobox named 'garmin-stable' and mounts this workspace directory

NAME=garmin-stable
IMAGE="${1:-ubuntu:24.04}"
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Workspace dir: $WORKSPACE_DIR"

if ! command -v distrobox >/dev/null 2>&1; then
  echo "distrobox not found. Install it first: https://github.com/89luca89/distrobox#installation"
  exit 1
fi

if ! command -v podman >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
  echo "Neither podman nor docker found. Install one to use distrobox."
  exit 1
fi

echo "Creating distrobox '$NAME' with image $IMAGE and mounting workspace to /home/developer/host-workspace"

# Pass volume bind to the backend engine via distrobox-create's extra args
distrobox-create --name "$NAME" --image "$IMAGE" -- --volume "$WORKSPACE_DIR":/home/developer/host-workspace || true

echo "Done. Enter with: distrobox-enter --name $NAME"

echo "Inside the container you can access your workspace at /home/developer/host-workspace"

exit 0
