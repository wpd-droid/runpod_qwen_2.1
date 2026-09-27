FROM runpod/worker-comfyui:5.10.0-base

# ------------------------------------------------------------
# RunPod GitHub deployment compatibility
# ------------------------------------------------------------

RUN mv /handler.py /worker_comfyui_handler.py
COPY handler.py /handler.py

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_INPUT=1 \
    PYTHONUNBUFFERED=1


# ------------------------------------------------------------
# Update ComfyUI for Qwen Image 2.1
# ------------------------------------------------------------

WORKDIR /comfyui

RUN git fetch --depth 1 origin tag v0.37.0 \
    && git checkout --force v0.37.0

RUN python -m pip install --no-cache-dir \
    -r /comfyui/requirements.txt


# ------------------------------------------------------------
# Verify the RunPod Torch / CUDA environment
#
# Expected:
# Python 3.12
# Torch 2.11.x
# CUDA 12.8
# ------------------------------------------------------------

RUN python - <<'PY'
import sys
import torch

print("Python:", sys.version)
print("Torch:", torch.__version__)
print("Torch CUDA:", torch.version.cuda)

assert sys.version_info[:2] == (3, 12), \
    f"Expected Python 3.12, got {sys.version}"

assert torch.__version__.startswith("2.11."), \
    f"Expected Torch 2.11.x, got {torch.__version__}"

assert torch.version.cuda == "12.8", \
    f"Expected CUDA 12.8 Torch build, got {torch.version.cuda}"

print("Runtime matches SageAttention wheel target.")
PY


# ------------------------------------------------------------
# SageAttention 2.2.0
#
# IMPORTANT:
# Do NOT compile SageAttention here.
#
# Astral publishes pre-built Linux wheels matched to:
#   Python 3.12
#   Torch 2.11
#   CUDA 12.8
#
# --only-binary prevents pip from falling back to another
# source compilation if the requested wheel is unavailable.
#
# --no-deps prevents SageAttention from replacing our
# working RunPod Torch installation.
# ------------------------------------------------------------

RUN python -m pip install \
    --no-cache-dir \
    --no-deps \
    --only-binary=:all: \
    --index-url https://wheels.astral.sh/simple/cu128/ \
    "sageattention==2.2.0+cu.12.8.torch.2.11"


# ------------------------------------------------------------
# Verify SageAttention + Ada / SM89 extension
# ------------------------------------------------------------

RUN python - <<'PY'
import importlib
import importlib.metadata
import torch
import sageattention

print("SageAttention:",
      importlib.metadata.version("sageattention"))
print("Torch:", torch.__version__)
print("Torch CUDA:", torch.version.cuda)

# Make sure the compiled Ada extension is actually in the wheel.
importlib.import_module("sageattention._qattn_sm89")

print("SageAttention SM89 extension loaded successfully.")
PY


# ------------------------------------------------------------
# Custom nodes
# ------------------------------------------------------------

WORKDIR /comfyui/custom_nodes


# Sprite Maker
RUN git clone --depth 1 \
    https://github.com/wpd-droid/sprite_maker_nodes.git \
    /comfyui/custom_nodes/sprite_maker_nodes


# Attention Optimizer
RUN git clone --depth 1 \
    https://github.com/D-Ogi/ComfyUI-Attention-Optimizer.git \
    /comfyui/custom_nodes/ComfyUI-Attention-Optimizer


# ------------------------------------------------------------
# Install custom-node requirements
# ------------------------------------------------------------

RUN for d in /comfyui/custom_nodes/*; do \
      if [ -f "$d/requirements.txt" ]; then \
        echo "Installing requirements for $d"; \
        python -m pip install --no-cache-dir \
          -r "$d/requirements.txt"; \
      fi; \
    done


# ------------------------------------------------------------
# Verify Attention Optimizer
# ------------------------------------------------------------

RUN test -f \
      /comfyui/custom_nodes/ComfyUI-Attention-Optimizer/__init__.py \
    && test -f \
      /comfyui/custom_nodes/ComfyUI-Attention-Optimizer/nodes.py \
    && echo "Attention Optimizer installed successfully"


# ------------------------------------------------------------
# Model directories
# ------------------------------------------------------------

RUN mkdir -p \
    /comfyui/models/diffusion_models \
    /comfyui/models/text_encoders \
    /comfyui/models/vae


# ------------------------------------------------------------
# Qwen Image 2.1 diffusion model
# ------------------------------------------------------------

RUN wget -O \
    /comfyui/models/diffusion_models/qwen_image_2.1_int8_convrot.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_int8_convrot.safetensors"


# ------------------------------------------------------------
# Qwen3-VL text encoder
# ------------------------------------------------------------

RUN wget -O \
    /comfyui/models/text_encoders/qwen3vl_8b_int8_convrot.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3vl_8b_int8_convrot.safetensors"


# ------------------------------------------------------------
# Qwen Image 2.1 VAE
# ------------------------------------------------------------

RUN wget -O \
    /comfyui/models/vae/qwen_image_2.1_vae_bf16.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"


WORKDIR /comfyui
