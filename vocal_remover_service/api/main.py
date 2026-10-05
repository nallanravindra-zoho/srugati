import os
import uuid
from datetime import datetime, timezone

import google.auth
import google.auth.transport.requests
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from google.cloud import storage, firestore, pubsub_v1

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
UPLOAD_BUCKET = os.environ["UPLOAD_BUCKET"]
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]
PUBSUB_TOPIC = os.environ["PUBSUB_TOPIC"]

ALLOWED_CONTENT_TYPES = {
    "audio/mpeg", "audio/wav", "audio/x-wav", "audio/flac", "audio/mp4", "audio/x-m4a",
    "video/mp4",  # browsers report .mp4 as video/mp4 even when it's audio-only
}
MAX_UPLOAD_BYTES = 500 * 1024 * 1024  # 500MB
UPLOAD_URL_EXPIRATION_SECONDS = 900

app = FastAPI(title="Vocal Remover API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get("CORS_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)

storage_client = storage.Client()
db = firestore.Client()
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, PUBSUB_TOPIC)

# Cloud Run's default credentials carry a token, not a private key, so
# generate_signed_url can't sign locally. Route signing through the IAM
# signBlob API instead by passing the runtime service account's email and a
# fresh access token (requires roles/iam.serviceAccountTokenCreator on
# itself, granted in Terraform).
_credentials, _ = google.auth.default()


def _signed_url(blob, method="GET", content_type=None, expiration=3600):
    _credentials.refresh(google.auth.transport.requests.Request())
    kwargs = {
        "version": "v4",
        "expiration": expiration,
        "method": method,
        "service_account_email": _credentials.service_account_email,
        "access_token": _credentials.token,
    }
    if content_type:
        kwargs["content_type"] = content_type
    return blob.generate_signed_url(**kwargs)


class CreateJobRequest(BaseModel):
    filename: str
    content_type: str


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/jobs")
def create_job(req: CreateJobRequest):
    # Cloud Run caps direct request bodies at 32MB, well under real song
    # files, so the browser uploads straight to GCS via this signed URL
    # instead of routing bytes through the API.
    if req.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(400, f"Unsupported content type: {req.content_type}")

    job_id = str(uuid.uuid4())
    ext = os.path.splitext(req.filename or "")[1] or ".audio"
    blob_path = f"{job_id}/input{ext}"

    bucket = storage_client.bucket(UPLOAD_BUCKET)
    blob = bucket.blob(blob_path)
    upload_url = _signed_url(
        blob, method="PUT", content_type=req.content_type, expiration=UPLOAD_URL_EXPIRATION_SECONDS
    )

    now = datetime.now(timezone.utc)
    db.collection("jobs").document(job_id).set(
        {
            "status": "awaiting_upload",
            "created_at": now,
            "updated_at": now,
            "input_path": blob_path,
            "content_type": req.content_type,
            "original_filename": req.filename,
            "error": None,
        }
    )

    return {"job_id": job_id, "upload_url": upload_url, "content_type": req.content_type}


@app.post("/jobs/{job_id}/confirm")
def confirm_upload(job_id: str):
    doc_ref = db.collection("jobs").document(job_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(404, "Job not found")
    data = doc.to_dict()
    if data["status"] != "awaiting_upload":
        raise HTTPException(400, f"Job is not awaiting upload (status: {data['status']})")

    bucket = storage_client.bucket(UPLOAD_BUCKET)
    blob = bucket.blob(data["input_path"])
    blob.reload()
    if not blob.exists():
        raise HTTPException(400, "Upload not found — did the PUT to upload_url complete?")

    if blob.size == 0:
        blob.delete()
        raise HTTPException(400, "Empty file")
    if blob.size > MAX_UPLOAD_BYTES:
        blob.delete()
        raise HTTPException(400, f"File too large (max {MAX_UPLOAD_BYTES // (1024 * 1024)}MB)")

    now = datetime.now(timezone.utc)
    doc_ref.update({"status": "queued", "updated_at": now})

    publisher.publish(
        topic_path,
        b"",
        job_id=job_id,
        input_bucket=UPLOAD_BUCKET,
        input_path=data["input_path"],
        output_bucket=OUTPUT_BUCKET,
    )

    return {"job_id": job_id, "status": "queued"}


@app.get("/jobs/{job_id}")
def get_job(job_id: str):
    doc = db.collection("jobs").document(job_id).get()
    if not doc.exists:
        raise HTTPException(404, "Job not found")
    data = doc.to_dict()
    result = {"job_id": job_id, "status": data["status"]}
    if data["status"] == "processing":
        result["progress"] = data.get("progress", 0)
        result["stage"] = data.get("stage")
    if data["status"] == "failed":
        result["error"] = data.get("error")
    if data["status"] == "done":
        bucket = storage_client.bucket(OUTPUT_BUCKET)
        result["stems"] = {}
        for stem in ("vocals", "instrumental"):
            blob = bucket.blob(f"{job_id}/{stem}.wav")
            if blob.exists():
                result["stems"][stem] = _signed_url(blob)
    return result


@app.post("/jobs/{job_id}/cancel")
def cancel_job(job_id: str):
    """
    Marks the job cancelled. A queued job is then skipped by the worker; a
    running one has its Demucs process stopped by the worker's watcher.
    Finished jobs are left alone.
    """
    doc_ref = db.collection("jobs").document(job_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(404, "Job not found")
    status = doc.to_dict()["status"]
    if status in ("awaiting_upload", "queued", "processing"):
        doc_ref.update({"status": "cancelled", "updated_at": datetime.now(timezone.utc)})
        return {"job_id": job_id, "status": "cancelled"}
    return {"job_id": job_id, "status": status}
