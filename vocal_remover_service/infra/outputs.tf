output "api_url" {
  value = google_cloud_run_v2_service.api.uri
}

output "worker_url" {
  value = google_cloud_run_v2_service.worker.uri
}

output "uploads_bucket" {
  value = google_storage_bucket.uploads.name
}

output "outputs_bucket" {
  value = google_storage_bucket.outputs.name
}

output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/vocal-remover"
}
