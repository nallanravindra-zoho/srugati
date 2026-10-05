import base64
import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timezone

from fastapi import FastAPI, Request, HTTPException
from google.cloud import storage, firestore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("worker")

DEMUCS_MODEL = os.environ.get("DEMUCS_MODEL", "htdemucs")
DEVICE = os.environ.get("DEMUCS_DEVICE", "cpu")

app = FastAPI(title="Vocal Remover Worker")

storage_client = storage.Client()
db = firestore.Client()


def mark_job(job_id: str, **fields):
    fields["updated_at"] = datetime.now(timezone.utc)
    db.collection("jobs").document(job_id).update(fields)


PROGRESS_RE = re.compile(r"(\d{1,3})%\|")
CANCEL_POLL_SECONDS = 3.0
PROGRESS_WRITE_SECONDS = 2.0


class JobCancelled(Exception):
    pass


def run_demucs(cmd, on_progress, is_cancelled, timeout=3300):
    """
    Runs Demucs, reporting its tqdm percentage via [on_progress] and stopping
    it as soon as [is_cancelled] turns true. Returns the captured stderr tail.
    """
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, bufsize=1)
    tail: list[str] = []

    def handle(part):
        if not part.strip():
            return
        tail.append(part)
        del tail[:-40]
        match = PROGRESS_RE.search(part)
        if match:
            on_progress(min(100, int(match.group(1))))

    def read_stderr():
        buf = ""
        while True:
            chunk = proc.stderr.read(256)
            if not chunk:
                break
            buf += chunk
            parts = re.split(r"[\r\n]", buf)
            buf = parts.pop()
            for part in parts:
                handle(part)
        handle(buf)

    reader = threading.Thread(target=read_stderr, daemon=True)
    reader.start()

    started = time.monotonic()
    last_check = 0.0
    try:
        while proc.poll() is None:
            time.sleep(0.5)
            now = time.monotonic()
            if now - started > timeout:
                proc.kill()
                raise RuntimeError("demucs timed out")
            if now - last_check >= CANCEL_POLL_SECONDS:
                last_check = now
                if is_cancelled():
                    proc.kill()
                    proc.wait()
                    raise JobCancelled()
    finally:
        if proc.poll() is None:
            proc.kill()
        reader.join(timeout=5)

    if proc.returncode != 0:
        raise RuntimeError(f"demucs failed: {' | '.join(tail)[-2000:]}")


def job_is_cancelled(job_id: str) -> bool:
    doc = db.collection("jobs").document(job_id).get()
    return doc.exists and doc.to_dict().get("status") == "cancelled"


def run_separation(job_id: str, input_bucket: str, input_path: str, output_bucket: str):
    workdir = tempfile.mkdtemp(prefix=f"job-{job_id}-")
    try:
        if job_is_cancelled(job_id):
            raise JobCancelled()
        mark_job(job_id, status="processing", progress=0, stage="downloading", error=None)
        local_input = os.path.join(workdir, os.path.basename(input_path))
        storage_client.bucket(input_bucket).blob(input_path).download_to_filename(local_input)
        if job_is_cancelled(job_id):
            raise JobCancelled()

        out_dir = os.path.join(workdir, "out")
        cmd = [
            "python3", "-m", "demucs",
            "-n", DEMUCS_MODEL,
            "--two-stems", "vocals",
            "-d", DEVICE,
            "-o", out_dir,
            local_input,
        ]
        logger.info("Running: %s", " ".join(cmd))

        last_write = [0.0, -1]

        def on_progress(percent):
            now = time.monotonic()
            if percent != last_write[1] and now - last_write[0] >= PROGRESS_WRITE_SECONDS:
                last_write[0], last_write[1] = now, percent
                try:
                    # Never overwrite a cancel that landed meanwhile.
                    db.collection("jobs").document(job_id).update(
                        {"progress": percent, "stage": "separating", "updated_at": datetime.now(timezone.utc)}
                    )
                except Exception:
                    logger.exception("progress write failed")

        run_demucs(cmd, on_progress, lambda: job_is_cancelled(job_id))

        track_name = os.path.splitext(os.path.basename(local_input))[0]
        stem_dir = os.path.join(out_dir, DEMUCS_MODEL, track_name)
        vocals_path = os.path.join(stem_dir, "vocals.wav")
        instrumental_path = os.path.join(stem_dir, "no_vocals.wav")

        mark_job(job_id, progress=100, stage="finishing")
        out_bucket = storage_client.bucket(output_bucket)
        out_bucket.blob(f"{job_id}/vocals.wav").upload_from_filename(vocals_path)
        out_bucket.blob(f"{job_id}/instrumental.wav").upload_from_filename(instrumental_path)

        if job_is_cancelled(job_id):
            raise JobCancelled()
        mark_job(job_id, status="done", progress=100, stage="done", error=None)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/process")
async def process(request: Request):
    envelope = await request.json()
    message = envelope.get("message")
    if not message:
        raise HTTPException(400, "Bad Pub/Sub message format")

    attributes = message.get("attributes", {})
    job_id = attributes.get("job_id")
    input_bucket = attributes.get("input_bucket")
    input_path = attributes.get("input_path")
    output_bucket = attributes.get("output_bucket")

    if not all([job_id, input_bucket, input_path, output_bucket]):
        logger.error("Missing attributes, dropping message: %s", attributes)
        return {"status": "dropped"}

    # Pub/Sub's push ack deadline caps at 600s, well under how long CPU
    # inference can take on a long track, so redelivery of an in-flight or
    # already-finished job is expected. Treat it as a no-op rather than
    # reprocessing.
    existing = db.collection("jobs").document(job_id).get()
    if existing.exists and existing.to_dict().get("status") in ("processing", "done", "cancelled"):
        logger.info("Job %s already %s, skipping duplicate delivery", job_id, existing.to_dict().get("status"))
        return {"status": "already_in_progress"}

    try:
        run_separation(job_id, input_bucket, input_path, output_bucket)
    except JobCancelled:
        logger.info("Job %s cancelled", job_id)
        try:
            mark_job(job_id, status="cancelled")
        except Exception:
            logger.exception("Failed to record cancellation for job %s", job_id)
    except Exception as exc:
        logger.exception("Job %s failed", job_id)
        try:
            mark_job(job_id, status="failed", error=str(exc)[:2000])
        except Exception:
            logger.exception("Failed to record failure for job %s", job_id)

    # Ack regardless so Pub/Sub doesn't retry a job we already recorded as failed.
    return {"status": "acked"}
