# syntax=docker/dockerfile:1.7
#
# A thin RunPod template. Almost nothing lives in this image on purpose -
# ComfyUI, its venv, models and custom nodes all live on your network volume at
# /workspace, so everything you do there persists.
#
# The image only provides the GPU plumbing you cannot easily install yourself:
# CUDA 13, Python 3.12, and a torch build that works on Blackwell cards.
#
# Base pinned by digest so it cannot move under you.
#   runpod/comfyui:1.4.6-cuda13.0
#     ubuntu 24.04 + CUDA 13-0, Python 3.12
#     torch 2.10.0+cu130 / torchvision 0.25.0+cu130 / torchaudio 2.10.0+cu130
#     JupyterLab, sshd

FROM --platform=linux/amd64 runpod/comfyui:1.4.6-cuda13.0@sha256:0bf75436da591e0f26d299af3741e07cb8ce8ce36566d1a7d8d78aae458e5d67

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends git git-lfs rsync \
 && rm -rf /var/lib/apt/lists/*

COPY start.sh /opt/start.sh
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/start.sh /opt/entrypoint.sh

# --- Settings you can change in the RunPod template ---------------------------
# COMFYUI_REF        which ComfyUI version to install the FIRST time.
#                    empty = latest. Or a tag like v0.33.1, or a commit.
# INSTALL_REQS       auto   = only when the venv is newly created (default)
#                    always = every boot (use after you update ComfyUI yourself)
#                    never  = never
# USE_CK_ATTENTION   1 = fast Comfy Kitchen attention (default). 0 = off.
# ENABLE_JUPYTER     1 = JupyterLab on port 8888 (default)
# JUPYTER_TOKEN      password for JupyterLab. Empty = no password.
# COMFYUI_EXTRA_ARGS anything extra to pass to ComfyUI
ENV COMFYUI_REF="" \
    INSTALL_REQS=auto \
    USE_CK_ATTENTION=1 \
    ENABLE_JUPYTER=1 \
    JUPYTER_TOKEN="" \
    COMFYUI_PORT=8188 \
    COMFYUI_EXTRA_ARGS=""

# The base image sets WORKDIR to /workspace/runpod-slim; we want /workspace.
WORKDIR /workspace

EXPOSE 8188 8888 22
ENTRYPOINT ["/opt/entrypoint.sh"]
