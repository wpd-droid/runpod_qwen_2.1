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
# RTX 4090 / Ada compile settings
# ------------------------------------------------------------

ENV TORCH_CUDA_ARCH_LIST="8.9" \
    EXT_PARALLEL=4 \
    MAX_JOBS=8 \
    NVCC_APPEND_FLAGS="--threads 8" \
    CUDA_HOME="/usr/local/cuda" \
    PATH="/usr/local/cuda/bin:${PATH}"


# ------------------------------------------------------------
# Install CUDA 12.8 compiler toolchain
#
# The RunPod base includes CUDA runtime support but not nvcc.
# SageAttention requires nvcc to build its CUDA extensions.
# ------------------------------------------------------------

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        wget \
        gnupg \
        ca-certificates \
        git \
    && wget -qO /usr/share/keyrings/cuda-archive-keyring.gpg \
        https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/ /" \
        > /etc/apt/sources.list.d/cuda.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        cuda-nvcc-12-8 \
        cuda-cudart-dev-12-8 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sfn /usr/local/cuda-12.8 /usr/local/cuda

RUN nvcc --version


# ------------------------------------------------------------
# Update ComfyUI for Qwen Image 2.1
# ------------------------------------------------------------

WORKDIR /comfyui

RUN git fetch --depth 1 origin tag v0.37.0 \
    && git checkout --force v0.37.0

RUN python -m pip install --no-cache-dir \
    -r /comfyui/requirements.txt


# ------------------------------------------------------------
# Build dependencies for SageAttention
# ------------------------------------------------------------

RUN python -m pip install --no-cache-dir \
    ninja \
    packaging \
    wheel \
    setuptools


# ------------------------------------------------------------
# SageAttention 2++
#
# Build directly from upstream source for RTX 4090 / SM89.
# ------------------------------------------------------------

RUN git clone --depth 1 \
        https://github.com/thu-ml/SageAttention.git \
        /tmp/SageAttention \
    && cd /tmp/SageAttention \
    && python -m pip install \
        --no-cache-dir \
        --no-build-isolation \
        . \
    && rm -rf /tmp/SageAttention


# ------------------------------------------------------------
# Verify Torch / CUDA / SageAttention
# ------------------------------------------------------------

RUN python - <<'PY'
import torch
import sageattention

print("Torch:", torch.__version__)
print("Torch CUDA:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
print("SageAttention import successful")
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
# Verify Attention Optimizer is present
# ------------------------------------------------------------

RUN echo "Checking Attention Optimizer..." \
    && ls -lah /comfyui/custom_nodes/ComfyUI-Attention-Optimizer \
    && test -f /comfyui/custom_nodes/ComfyUI-Attention-Optimizer/__init__.py \
    && echo "Attention Optimizer files present"


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
