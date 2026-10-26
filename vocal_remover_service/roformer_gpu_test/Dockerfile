# Test image: RoFormer vocal separation on an NVIDIA L4 (Cloud Run GPU job).
FROM pytorch/pytorch:2.4.1-cuda12.1-cudnn9-runtime
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg libsndfile1 build-essential && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "audio-separator[gpu]" google-cloud-storage
COPY run.py /app/run.py
CMD ["python", "-u", "/app/run.py"]
