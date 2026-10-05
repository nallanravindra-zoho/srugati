terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Storage: uploads and outputs, both auto-deleted after N hours (privacy + cost control) ---

resource "google_storage_bucket" "uploads" {
  name          = "${var.project_id}-uploads"
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true

  # The browser PUTs the file straight to this bucket via a signed URL
  # (Cloud Run caps request bodies at 32MB, too small for real songs), so
  # the bucket itself needs to allow that cross-origin PUT.
  cors {
    origin          = ["*"]
    method          = ["PUT"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }

  lifecycle_rule {
    condition { age = var.retention_days }
    action { type = "Delete" }
  }
}

resource "google_storage_bucket" "outputs" {
  name          = "${var.project_id}-outputs"
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition { age = var.retention_days }
    action { type = "Delete" }
  }
}

# --- Artifact Registry for container images ---

resource "google_artifact_registry_repository" "images" {
  repository_id = "vocal-remover"
  location      = var.region
  format        = "DOCKER"
}

# --- Pub/Sub job queue ---

resource "google_pubsub_topic" "separation_jobs" {
  name = "separation-jobs"
}

resource "google_pubsub_subscription" "worker_push" {
  name  = "separation-jobs-worker-push"
  topic = google_pubsub_topic.separation_jobs.name

  ack_deadline_seconds = 600

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.worker.uri}/process"
    oidc_token {
      service_account_email = google_service_account.pubsub_invoker.email
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  expiration_policy {
    ttl = "" # never expires
  }
}

# --- Service accounts ---

resource "google_service_account" "api" {
  account_id   = "vocal-remover-api"
  display_name = "Vocal Remover API (Cloud Run, no GPU)"
}

resource "google_service_account" "worker" {
  account_id   = "vocal-remover-worker"
  display_name = "Vocal Remover GPU Worker (Cloud Run + Demucs)"
}

resource "google_service_account" "pubsub_invoker" {
  account_id   = "vocal-remover-pubsub-invoker"
  display_name = "Identity Pub/Sub uses to push into the worker"
}

# API: write uploads, read/write job state, publish jobs
resource "google_storage_bucket_iam_member" "api_uploads_writer" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.api.email}"
}

resource "google_storage_bucket_iam_member" "api_outputs_reader" {
  bucket = google_storage_bucket.outputs.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.api.email}"
}

resource "google_pubsub_topic_iam_member" "api_publisher" {
  topic  = google_pubsub_topic.separation_jobs.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.api.email}"
}

# Worker: read uploads, write outputs
resource "google_storage_bucket_iam_member" "worker_uploads_reader" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.worker.email}"
}

resource "google_storage_bucket_iam_member" "worker_outputs_writer" {
  bucket = google_storage_bucket.outputs.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.worker.email}"
}

# Firestore access for both API and worker
resource "google_project_iam_member" "api_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Lets the API sign GCS download URLs via the IAM signBlob API — Cloud
# Run's default credentials carry a token, not a private key, so this
# self-impersonation permission is required for generate_signed_url to work.
resource "google_service_account_iam_member" "api_signs_own_urls" {
  service_account_id = google_service_account.api.name
  role                = "roles/iam.serviceAccountTokenCreator"
  member              = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "worker_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.worker.email}"
}

# Let Pub/Sub's push identity invoke the worker
resource "google_cloud_run_v2_service_iam_member" "pubsub_invokes_worker" {
  name     = google_cloud_run_v2_service.worker.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pubsub_invoker.email}"
}

# --- Cloud Run: lightweight API (no GPU, public) ---

resource "google_cloud_run_v2_service" "api" {
  name                = "vocal-remover-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.api.email

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/vocal-remover/api:latest"
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "UPLOAD_BUCKET"
        value = google_storage_bucket.uploads.name
      }
      env {
        name  = "OUTPUT_BUCKET"
        value = google_storage_bucket.outputs.name
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.separation_jobs.name
      }
      env {
        name  = "CORS_ORIGINS"
        value = var.frontend_origin
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "api_public" {
  name     = google_cloud_run_v2_service.api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Cloud Run: CPU-only worker (Demucs, private, invoked only by Pub/Sub push) ---
# No GPU: stays on the free tier. Slower per job, which is fine since
# performance isn't a priority for this deployment.

resource "google_cloud_run_v2_service" "worker" {
  name                = "vocal-remover-worker"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account                  = google_service_account.worker.email
    timeout                          = "3600s" # CPU inference is much slower than GPU; long tracks need headroom
    max_instance_request_concurrency = 1

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/vocal-remover/worker:latest"
      env {
        name  = "DEMUCS_MODEL"
        value = "htdemucs"
      }
      env {
        name  = "DEMUCS_DEVICE"
        value = "cpu"
      }
      resources {
        limits = {
          cpu    = "4"
          memory = "4Gi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }
}

# No public IAM binding is granted on the worker service — only the
# Pub/Sub push identity (bound above) can invoke it.
