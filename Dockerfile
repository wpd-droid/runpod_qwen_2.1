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
# CUDA / compilation tuning for RTX 4090 (Ada / SM89)
# ------------------------------------------------------------

ENV TORCH_CUDA_ARCH_LIST="8.9" \
    MAX_JOBS=8 \
    NVCC_APPEND_FLAGS="--threads 8"


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
# SageAttention 2++ optimized for RTX 4090
#
# SageAttention 2.2 includes the CUDA FP8 path used by Ada
# GPUs such as the RTX 4090.
# ------------------------------------------------------------

RUN python -m pip install \
    --no-cache-dir \
    --no-build-isolation \
    "sageattention==2.2.0"


# ------------------------------------------------------------
# Verify SageAttention installed successfully
# ------------------------------------------------------------

RUN python - <<'PY'
import importlib.metadata
import sageattention

print("SageAttention version:",
      importlib.metadata.version("sageattention"))
print("SageAttention import successful")
PY


# ------------------------------------------------------------
# Custom nodes
# ------------------------------------------------------------

WORKDIR /comfyui/custom_nodes


# Sprite Maker
RUN git clone --depth 1 \
    https://github.com/wpd-droid/sprite_maker_nodes.git


# ------------------------------------------------------------
# Attention Optimizer
#
# Allows explicit selection of SageAttention CUDA backends
# instead of globally forcing ComfyUI's attention implementation.
# ------------------------------------------------------------

RUN git clone --depth 1 \
    https://github.com/D-Ogi/ComfyUI-Attention-Optimizer.git


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
