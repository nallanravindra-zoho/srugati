variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "vocal-remover-app-6892"
}

variable "region" {
  description = "GCP region (must have Cloud Run L4 GPU availability)"
  type        = string
  default     = "us-central1"
}

variable "retention_days" {
  description = "Days before uploaded/output audio is auto-deleted from Cloud Storage"
  type        = number
  default     = 1
}

variable "frontend_origin" {
  description = "Origin(s) allowed to call the API (CORS), comma-separated"
  type        = string
  default     = "*"
}
