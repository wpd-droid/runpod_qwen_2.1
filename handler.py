import os
import sys
import runpod


# RunPod's GitHub deployment scanner looks for this call in the repository.
# The actual ComfyUI serverless implementation is supplied by the
# runpod/worker-comfyui base image.
def _github_detection_handler(event):
    return {
        "error": "This compatibility handler should delegate to worker-comfyui."
    }


def _runpod_github_detection_marker():
    runpod.serverless.start({
        "handler": _github_detection_handler
    })


if __name__ == "__main__":
    # Replace this process with worker-comfyui's real serverless handler.
    os.execv(
        sys.executable,
        [
            sys.executable,
            "-u",
            "/worker_comfyui_handler.py",
            *sys.argv[1:]
        ]
    )
