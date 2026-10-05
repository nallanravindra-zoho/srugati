# Vocal Remover

Separates a song into vocals and instrumental tracks using Demucs (htdemucs),
served from a GPU-backed Cloud Run worker.

## System shape

```
frontend (React/Vite)
   -> api (Cloud Run, no GPU) -- uploads audio to GCS, writes a Firestore job doc, publishes to Pub/Sub
   -> Pub/Sub topic "separation-jobs"
   -> worker (Cloud Run w/ L4 GPU) -- Pub/Sub push subscription, runs Demucs, writes stems to GCS, updates Firestore
   -> frontend polls GET /jobs/{id} until status is "done", then plays/downloads signed URLs
```

## GCP project

- Project: `vocal-remover-app-6892`
- Account: `budgeting.tool.cyberknight@gmail.com`
- Region: `us-central1`
- Billing account, Firestore (native mode), and required APIs (Cloud Run, Pub/Sub,
  Storage, Artifact Registry, Firestore, Cloud Build, Compute) are already
  provisioned on this project.

## Layout

- `api/` — FastAPI service, Cloud Run, no GPU. Handles upload + job status.
- `worker/` — FastAPI service wrapping Demucs, Cloud Run w/ NVIDIA L4 GPU.
  Invoked only by the Pub/Sub push subscription (not publicly reachable).
- `frontend/` — Vite + React upload UI, polls job status, plays/downloads stems.
- `infra/` — Terraform for storage buckets, Pub/Sub, Artifact Registry, IAM,
  and both Cloud Run services.

## Before first deploy

1. **Request Cloud Run GPU quota.** New projects start with zero L4 GPU quota
   for Cloud Run in most regions. Request it in the GCP Console
   (IAM & Admin -> Quotas, filter for "Total Nvidia L4 GPU allocation, per
   project per region" under the Cloud Run Admin API) before running
   `infra/deploy.sh`, or the worker service creation will fail.
2. **Accept the Xcode license** (macOS only, blocks `git` and some builds):
   ```bash
   sudo xcodebuild -license
   ```
3. Make sure Docker Desktop is running (worker image build needs it, and is
   large — CUDA + PyTorch + prefetched Demucs weights).

## Deploy

```bash
cd infra
./deploy.sh
```

This bootstraps Artifact Registry/storage/Pub/Sub/service accounts, builds and
pushes both container images, then applies the full Terraform config
(Cloud Run services + IAM + the Pub/Sub push subscription, which needs the
worker's URL to exist first).

## Local development

**API** (needs `gcloud auth application-default login` for local GCP creds):
```bash
cd api
pip install -r requirements.txt
GCP_PROJECT_ID=vocal-remover-app-6892 \
UPLOAD_BUCKET=vocal-remover-app-6892-uploads \
OUTPUT_BUCKET=vocal-remover-app-6892-outputs \
PUBSUB_TOPIC=separation-jobs \
uvicorn main:app --reload --port 8080
```

**Worker** — requires a CUDA GPU; not practical to run locally on most
machines. Test it end-to-end via the deployed Cloud Run service instead.

**Frontend**:
```bash
cd frontend
cp .env.example .env.local   # point VITE_API_URL at your API
npm run dev
```

## Notes / known limitations

Per the source-separation model itself (not this app's plumbing): expect
bleed on overlapping vocal/instrument frequencies, reverb/delay residue left
in the instrumental, and worse separation on old/mono/heavily compressed
masters. This is inherent to current Demucs-family models, not a bug to
chase — aim is best-in-class, not flawless.

Uploaded audio and output stems auto-delete from Cloud Storage after
`retention_days` (default 1 day, set in `infra/variables.tf`).
