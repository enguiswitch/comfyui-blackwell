#!/usr/bin/env bash
# Tiny bootstrap. Its only job is to hand over to start.sh on your volume, so
# you can edit the boot script on the pod without rebuilding the image.
#
# Same rule as everything else here: if it is already there, don't overwrite it.
set -euo pipefail

WORKSPACE="${COMFYUI_WORKSPACE:-/workspace}"
mkdir -p "$WORKSPACE"
TARGET="$WORKSPACE/start.sh"

if [[ -f "$TARGET" ]]; then
    printf '\n\033[1;36m==>\033[0m Using your %s\n' "$TARGET"
    printf '    (delete it to restore the built-in version)\n'
else
    cp /opt/start.sh "$TARGET"
    chmod +x "$TARGET"
    printf '\n\033[1;36m==>\033[0m Installed %s\n' "$TARGET"
    printf '    (edit it freely - it persists, and the image will not overwrite it)\n'
fi

exec bash "$TARGET"
