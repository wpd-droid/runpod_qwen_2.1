# clean RunPod Serverless base containing ComfyUI worker
FROM runpod/worker-comfyui:5.10.0-base

# ------------------------------------------------------------
# Qwen Image 2.1 needs a newer ComfyUI than older worker builds
# ------------------------------------------------------------
WORKDIR /comfyui

RUN git fetch --depth 1 origin tag v0.37.0 \
    && git checkout --force v0.37.0

# install/update ComfyUI Python requirements into the worker runtime env
RUN python -m pip install --no-cache-dir -r /comfyui/requirements.txt


# ------------------------------------------------------------
# Custom nodes
# ------------------------------------------------------------
WORKDIR /comfyui/custom_nodes

RUN git clone \
    https://github.com/wpd-droid/sprite_maker_nodes.git


# install requirements for any custom nodes that provide them
WORKDIR /comfyui

RUN for d in /comfyui/custom_nodes/*; do \
      if [ -f "$d/requirements.txt" ]; then \
        python -m pip install --no-cache-dir -r "$d/requirements.txt"; \
      fi; \
    done


# ------------------------------------------------------------
# Model folders
# ------------------------------------------------------------
RUN mkdir -p \
    /comfyui/models/unet \
    /comfyui/models/diffusion_models \
    /comfyui/models/clip \
    /comfyui/models/text_encoders \
    /comfyui/models/vae


# ------------------------------------------------------------
# Qwen Image 2.1 INT8 diffusion model
# ------------------------------------------------------------
RUN wget -O /comfyui/models/diffusion_models/qwen_image_2.1_int8_convrot.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/diffusion_models/qwen_image_2.1_int8_convrot.safetensors"


# ------------------------------------------------------------
# Qwen3-VL INT8 text encoder
# ------------------------------------------------------------
RUN wget -O /comfyui/models/text_encoders/qwen3vl_8b_int8_convrot.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/qwen3vl_8b_int8_convrot.safetensors"


# ------------------------------------------------------------
# Qwen Image 2.1 VAE
# ------------------------------------------------------------
RUN wget -O /comfyui/models/vae/qwen_image_2.1_vae_bf16.safetensors \
    "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors"


# ------------------------------------------------------------
# Return to normal ComfyUI working directory
#
# Do NOT override CMD or ENTRYPOINT.
# runpod/worker-comfyui already provides the RunPod Serverless handler.
# ------------------------------------------------------------
WORKDIR /comfyui
