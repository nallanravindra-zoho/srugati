#!/usr/bin/env bash
# Builds and deploys the Vocal Remover app. Run from infra/.
#
# Order matters: Cloud Run services reference container images by tag, so
# the images must exist in Artifact Registry before `terraform apply` can
# create/update those services. This script bootstraps the registry first,
# builds+pushes images, then applies the rest.
set -euo pipefail

PROJECT_ID="srugati-app"
REGION="us-central1"
REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/vocal-remover"

echo "==> 1/4 Bootstrapping Artifact Registry + storage + pubsub (no Cloud Run yet)"
terraform apply \
  -target=google_artifact_registry_repository.images \
  -target=google_storage_bucket.uploads \
  -target=google_storage_bucket.outputs \
  -target=google_pubsub_topic.separation_jobs \
  -target=google_service_account.api \
  -target=google_service_account.worker \
  -target=google_service_account.pubsub_invoker

echo "==> 2/4 Configuring Docker auth for Artifact Registry"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

echo "==> 3/4 Building and pushing images (worker image is large — CUDA + PyTorch + Demucs weights)"
docker build -t "${REPO}/api:latest" ../api
docker push "${REPO}/api:latest"

docker build -t "${REPO}/worker:latest" ../worker
docker push "${REPO}/worker:latest"

echo "==> 4/4 Applying full infrastructure (Cloud Run services, IAM, Pub/Sub push subscription)"
terraform apply

echo "Done. API URL:"
terraform output -raw api_url
