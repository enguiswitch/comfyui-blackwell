# comfyui-blackwell

A simple RunPod template for Blackwell GPUs (RTX 5090, RTX PRO 4500, RTX PRO 6000).

Everything lives on your network volume and stays there. The image only provides
the GPU plumbing: CUDA 13, Python 3.12, and a torch build that works on Blackwell.

## What happens when you start a pod

**First time:**
1. Installs ComfyUI into `/workspace/ComfyUI`
2. Creates a venv at `/workspace/ComfyUI/venv`
3. Installs the requirements
4. Starts ComfyUI + JupyterLab

**Every time after that:**
1. Sees ComfyUI is already there → leaves it completely alone
2. Sees the venv is already there → leaves it completely alone
3. Starts ComfyUI + JupyterLab

If you delete the venv but keep ComfyUI, it rebuilds just the venv and touches
nothing else.

**It never runs `git pull` and never updates anything on its own.** Updating is
your call, from a terminal, whenever you want.

## Where things are

```
/workspace/ComfyUI/                ComfyUI itself - edit it however you like
/workspace/ComfyUI/venv/           its Python environment
/workspace/ComfyUI/models/         your models
/workspace/ComfyUI/custom_nodes/   your custom nodes
/workspace/ComfyUI/user/           settings + saved workflows
/workspace/ComfyUI/output/         generated images
/workspace/start.sh                the boot script itself - editable
```

All of it persists. Nothing here is inside the image.

Even the boot script lives on the volume. On the very first run the image copies
it to `/workspace/start.sh`; after that it uses yours and never overwrites it.
Edit it on the pod and restart — no image rebuild. Delete it to get the built-in
one back.

## Doing things

Open a terminal in JupyterLab (port 8888), then:

```bash
cd /workspace/ComfyUI
source venv/bin/activate
```

Now you are in the same environment ComfyUI uses.

**Install a custom node**

```bash
cd /workspace/ComfyUI/custom_nodes
git clone https://github.com/owner/repo
pip install -r repo/requirements.txt      # if it has one
```

Restart the pod. It stays forever.

**Download a model**

```bash
cd /workspace/ComfyUI/models/checkpoints
wget <url>
```

**Update ComfyUI**

```bash
cd /workspace/ComfyUI
git pull
pip install -r requirements.txt
```

Restart the pod.

**Start over with a clean venv**

```bash
rm -rf /workspace/ComfyUI/venv
```

Restart the pod. It rebuilds the venv and leaves ComfyUI, models and nodes alone.

## RunPod template settings

| Setting | Value |
|---|---|
| Container image | `ghcr.io/<owner>/comfyui-blackwell:latest` |
| Container disk | 20 GB |
| Volume mount path | `/workspace` |
| HTTP ports | `8188` (ComfyUI), `8888` (JupyterLab) |
| TCP port | `22` (only if you want SSH) |

**Set the pod filter's CUDA Version to 13.0 or higher.** These cards need a
recent host driver, and that is a filter setting the image cannot control.

## Optional settings

Set these as environment variables in the RunPod template.

| Variable | Default | What it does |
|---|---|---|
| `COMFYUI_REF` | *(empty)* | Which ComfyUI version to install the **first** time. Empty = latest. Or `v0.33.1`, or a commit. |
| `INSTALL_REQS` | `auto` | `auto` = only for a new venv. `always` = every boot, use after you update ComfyUI yourself. `never` = never. |
| `ENABLE_JUPYTER` | `1` | JupyterLab on 8888 |
| `JUPYTER_TOKEN` | *(empty)* | Password for JupyterLab. Empty = no password. |
| *(automatic)* | — | No GPU detected (e.g. a CPU pod) adds `--cpu` by itself |
| `COMFYUI_EXTRA_ARGS` | *(empty)* | Extra ComfyUI flags, e.g. `--fast` |
| `PUBLIC_KEY` | *(empty)* | Your SSH public key, if you want SSH |

## Building the image

Push to `main`. GitHub Actions builds it and pushes to
`ghcr.io/<owner>/comfyui-blackwell`.

You will rarely need to rebuild. Not for ComfyUI, models or custom nodes — none
of that is in the image. Not even for boot-script changes, since `start.sh` lives
on your volume and is editable there. Really only if you change the base image
or the bootstrap.

## Files

```
Dockerfile                    the image (thin - just GPU plumbing)
entrypoint.sh                 hands over to /workspace/start.sh
start.sh                      the default boot script, copied to your volume once
.github/workflows/build.yml   builds and pushes to GHCR
```
