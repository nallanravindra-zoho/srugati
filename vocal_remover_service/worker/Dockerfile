# CPU-only worker (no GPU) to stay on GCP free tier. Slower than a GPU build,
# which is fine — performance is not a priority for this deployment.
FROM python:3.12-slim

# Avoid stale .pyc bytecode caches across build-time source patches.
ENV PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
# CPU-only torch/torchaudio wheels (much smaller than the CUDA build).
# demucs is pinned to 4.0.1 — newer releases pull in a Rust dependency
# (sphn) that fails to build in slim/minimal environments.
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch==2.5.1 torchaudio==2.5.1 && \
    pip install --no-cache-dir demucs==4.0.1 soundfile==0.12.1 fastapi==0.115.6 "uvicorn[standard]==0.34.0" \
        google-cloud-storage==2.19.0 google-cloud-firestore==2.20.0

# torchaudio depends on torchcodec for audio saving regardless of version,
# and torchcodec's native library fails to load on this base image (FFmpeg
# ABI mismatch). Patch demucs's save_audio to write via soundfile instead.
COPY patch_demucs_audio.py /tmp/patch_demucs_audio.py
RUN python3 /tmp/patch_demucs_audio.py

COPY main.py .

# Pre-warm the htdemucs model weights into the image so cold starts on
# Cloud Run don't have to download them on the request path.
RUN python3 -c "from demucs.pretrained import get_model; get_model('htdemucs')"

ENV PORT=8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT} --timeout-keep-alive 3600"]
