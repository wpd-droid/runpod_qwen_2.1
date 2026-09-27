FROM runpod/worker-comfyui:5.10.0-base

# ------------------------------------------------------------
# RunPod GitHub deployment compatibility
# ------------------------------------------------------------

RUN mv /handler.py /worker_comfyui_handler.py
COPY handler.py /handler.py


# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_INPUT=1 \
    PYTHONUNBUFFERED=1 \
    CC=/usr/bin/gcc


# ------------------------------------------------------------
# Runtime/build utilities
#
# gcc + Python headers are required because SageAttention's
# FP8 CUDA path uses Triton for Q/K quantization, and Triton
# builds a small runtime module on first execution.
#
# We DO NOT need nvcc or the CUDA development toolkit.
# ------------------------------------------------------------

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        python3.12-dev \
        git \
        wget \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*


# ------------------------------------------------------------
# Verify C compiler / Python headers
# ------------------------------------------------------------

RUN command -v gcc \
    && gcc --version \
    && test -f /usr/include/python3.12/Python.h \
    && echo "Triton runtime compiler requirements present"


# ------------------------------------------------------------
# Update ComfyUI for Qwen Image 2.1
# ------------------------------------------------------------

WORKDIR /comfyui

RUN git fetch --depth 1 origin tag v0.37.0 \
    && git checkout --force v0.37.0

RUN python -m pip install --no-cache-dir \
    -r /comfyui/requirements.txt


# ------------------------------------------------------------
# Verify base runtime
#
# SageAttention wheel below is specifically matched to:
#   Python 3.12
#   Torch 2.11
#   CUDA 12.8
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
# SageAttention 2.2
#
# IMPORTANT:
# Use a prebuilt SageAttention wheel.
# Do NOT compile SageAttention from source.
#
# --only-binary prevents pip from silently falling back
# to another source compilation.
#
# --no-deps prevents it from replacing the RunPod
# Torch installation.
# ------------------------------------------------------------

RUN python -m pip install \
    --no-cache-dir \
    --no-deps \
    --only-binary=:all: \
    --index-url https://wheels.astral.sh/simple/cu128/ \
    "sageattention==2.2.0+cu.12.8.torch.2.11"


# ------------------------------------------------------------
# Verify SageAttention / Ada SM89 extension
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

# RTX 4090 / Ada extension
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
# Final dependency sanity check
# ------------------------------------------------------------

RUN python - <<'PY'
import os
import torch
import sageattention
import triton

print("Torch:", torch.__version__)
print("Torch CUDA:", torch.version.cuda)
print("Triton:", triton.__version__)
print("CC:", os.environ.get("CC"))
print("SageAttention import: OK")
PY


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


# ------------------------------------------------------------
# Final working directory
# ------------------------------------------------------------

WORKDIR /comfyui
