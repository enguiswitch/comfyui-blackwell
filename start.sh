#!/usr/bin/env bash
#
# Everything lives on the network volume and persists:
#
#   /workspace/ComfyUI            ComfyUI itself - edit it freely
#   /workspace/ComfyUI/venv       its Python environment
#   /workspace/ComfyUI/models     your models
#   /workspace/ComfyUI/custom_nodes
#   /workspace/ComfyUI/user       settings + saved workflows
#   /workspace/ComfyUI/output     generated images
#
# This script installs a piece ONLY if it is missing. It never overwrites, never
# runs git pull, and never updates anything on its own. Updating is your call,
# whenever you feel like it, from a terminal.

set -euo pipefail

WORKSPACE="${COMFYUI_WORKSPACE:-/workspace}"
COMFY="$WORKSPACE/ComfyUI"
VENV="$COMFY/venv"
PY="$VENV/bin/python"

say()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

if ! mountpoint -q "$WORKSPACE" 2>/dev/null; then
    printf '\n\033[1;33m'
    echo "############################################################"
    echo "WARNING: $WORKSPACE is NOT a mounted network volume."
    echo "Everything will be LOST when this pod stops."
    echo "Fix: set the volume mount path to /workspace in the template."
    echo "############################################################"
    printf '\033[0m\n'
    sleep 5
fi
mkdir -p "$WORKSPACE"

# Keep pip's downloads on the volume so rebuilding the venv is fast next time.
export PIP_CACHE_DIR="$WORKSPACE/.cache/pip"
mkdir -p "$PIP_CACHE_DIR"

# ---------------------------------------------------------------------------
# 1. ComfyUI - install only if the folder is not there
# ---------------------------------------------------------------------------
if [[ -d "$COMFY/.git" ]]; then
    say "ComfyUI found - leaving it exactly as it is"
    info "$(git -C "$COMFY" log -1 --format='%h  %s' 2>/dev/null || echo 'local changes')"
else
    if [[ -d "$COMFY" ]]; then
        echo "ERROR: $COMFY exists but is not a git checkout. Move it aside or" >&2
        echo "       delete it, then restart the pod." >&2
        exit 1
    fi
    say "First run - installing ComfyUI into $COMFY"
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY"
    if [[ -n "${COMFYUI_REF:-}" ]]; then
        info "checking out $COMFYUI_REF"
        git -C "$COMFY" checkout "$COMFYUI_REF"
    fi
    info "installed $(git -C "$COMFY" log -1 --format='%h  %s')"
fi

# ---------------------------------------------------------------------------
# 2. venv - create only if missing, without touching anything else
# ---------------------------------------------------------------------------
NEW_VENV=0

if [[ -x "$PY" ]]; then
    say "venv found - leaving it exactly as it is"
    info "$("$PY" -V 2>&1)"
else
    say "Creating venv at $VENV"
    info "(uses the image's torch, so this takes seconds, not a 4 GB download)"
    rm -rf "$VENV"
    python3 -m venv --system-site-packages "$VENV"
    NEW_VENV=1
fi

export VIRTUAL_ENV="$VENV"
export PATH="$VENV/bin:$PATH"

# ---------------------------------------------------------------------------
# 3. Requirements - only for a fresh venv, unless you ask otherwise
# ---------------------------------------------------------------------------
should_install=0
case "${INSTALL_REQS:-auto}" in
    always) should_install=1 ;;
    never)  should_install=0 ;;
    *)      should_install=$NEW_VENV ;;
esac

if [[ "$should_install" == 1 ]]; then
    say "Installing ComfyUI requirements"
    "$PY" -m pip install --upgrade pip -q
    "$PY" -m pip install -r "$COMFY/requirements.txt"

    for req in "$COMFY"/custom_nodes/*/requirements.txt; do
        [[ -e "$req" ]] || continue
        info "custom node: $(basename "$(dirname "$req")")"
        "$PY" -m pip install -r "$req" || info "  (failed - that node may not load)"
    done
else
    say "Skipping requirements install (INSTALL_REQS=${INSTALL_REQS:-auto})"
    info "Updated ComfyUI yourself? Set INSTALL_REQS=always for one boot."
fi

# ---------------------------------------------------------------------------
# 4. GPU check
# ---------------------------------------------------------------------------
say "GPU"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null \
    | while read -r l; do info "$l"; done || info "no GPU visible"

"$PY" - <<'PY' || true
try:
    import torch
except ImportError:
    print("    WARNING: torch is not installed in the venv")
    raise SystemExit(0)
print(f"    torch {torch.__version__} (cuda {torch.version.cuda})")
if torch.cuda.is_available():
    a, b = torch.cuda.get_device_capability(0)
    print(f"    compute sm_{a}{b}")
    if (a, b) < (12, 0):
        print(f"    NOTE: sm_{a}{b} is not a Blackwell card.")
else:
    print("    WARNING: torch cannot see a GPU")
PY

# ---------------------------------------------------------------------------
# 5. SSH + JupyterLab
# ---------------------------------------------------------------------------
if [[ -n "${PUBLIC_KEY:-}" ]]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    ssh-keygen -A >/dev/null 2>&1 || true
    /usr/sbin/sshd 2>/dev/null && say "SSH ready on port 22" || true
fi

if [[ "${ENABLE_JUPYTER:-1}" == "1" ]]; then
    say "Starting JupyterLab on port 8888"
    [[ -z "${JUPYTER_TOKEN:-}" ]] && info "no password set (JUPYTER_TOKEN is empty)"

    # Run Jupyter with the SYSTEM python, not the venv.
    #
    # Jupyter is installed into /usr/local by the base image, and its server
    # extensions (terminals, contents) are registered relative to sys.prefix.
    # Launching from the venv moves sys.prefix and those extensions stop being
    # found - the Lab UI loads, but terminals and file opens return 404
    # ("Launcher error: not found" / "File Load Error ... not found").
    #
    # allow_origin + allow_remote_access are needed behind RunPod's proxy.
    # Terminals read $SHELL for which shell to spawn, and inherit Jupyter's
    # cwd - and the base image sets
    # WORKDIR to /workspace/runpod-slim - so start Jupyter from $WORKSPACE.
    export SHELL=/bin/bash
    ( cd "$WORKSPACE" && exec jupyter lab \
        --allow-root --ip=0.0.0.0 --port=8888 --no-browser \
        --ServerApp.token="${JUPYTER_TOKEN:-}" \
        --ServerApp.root_dir="$WORKSPACE" \
        --ServerApp.allow_origin='*' \
        --ServerApp.allow_remote_access=True \
        >"$WORKSPACE/jupyter.log" 2>&1 ) &

    # Make the ComfyUI venv selectable as a notebook kernel, so you still get at
    # it from Jupyter even though Jupyter itself runs outside it.
    "$PY" -m ipykernel install --name comfyui --display-name "ComfyUI (venv)" \
        >/dev/null 2>&1 || info "venv kernel unavailable (ipykernel not installed)"

    info "log: $WORKSPACE/jupyter.log"
fi

# ---------------------------------------------------------------------------
# 6. Start ComfyUI
# ---------------------------------------------------------------------------
ARGS=(--listen 0.0.0.0 --port "${COMFYUI_PORT:-8188}")

# Only add the flag if this ComfyUI version actually has it (0.32+), otherwise
# it would refuse to start.
if [[ "${USE_CK_ATTENTION:-1}" == "1" ]]; then
    if grep -q -- "use-ck-attention" "$COMFY/comfy/cli_args.py" 2>/dev/null; then
        ARGS+=(--use-ck-attention)
    else
        info "this ComfyUI version has no Comfy Kitchen attention - skipping the flag"
    fi
fi
if [[ -n "${COMFYUI_EXTRA_ARGS:-}" ]]; then
    read -r -a extra <<< "$COMFYUI_EXTRA_ARGS"
    ARGS+=("${extra[@]}")
fi

say "Starting ComfyUI on port ${COMFYUI_PORT:-8188}"
cd "$COMFY"
exec "$PY" main.py "${ARGS[@]}"
