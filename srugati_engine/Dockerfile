FROM python:3.11-slim-bookworm

RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    libsndfile1-dev \
    libfftw3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

COPY app ./app

ENV SRUGATI_OUTPUT_DIR=/tmp/srugati/outputs
ENV PORT=8080
EXPOSE 8080

# Hypercorn (not uvicorn) so the service can speak HTTP/2 cleartext (h2c) —
# Cloud Run's HTTP/1 path caps request/response bodies at 32MB with no way
# to raise it; HTTP/2 end-to-end (the --use-http2 deploy flag) removes that
# cap, which is what lets 100MB uploads through.
CMD ["sh", "-c", "hypercorn app.main:app --bind 0.0.0.0:${PORT:-8080}"]
