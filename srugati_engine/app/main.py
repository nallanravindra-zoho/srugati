"""SruGati Engine — pitch detection + independent pitch/tempo shifting for any audio or video file."""
from __future__ import annotations

import asyncio
import os
import re
import tempfile
import threading
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from starlette.background import BackgroundTask

from . import audio, pitch

app = FastAPI(title="SruGati Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    # Anything that escapes a route's own try/except still comes back as a
    # clean JSON message — never a bare stack trace or an infra error page.
    return JSONResponse(status_code=500, content={"detail": "Something went wrong processing your file. Please try again."})


OUTPUT_DIR = Path(os.getenv("SRUGATI_OUTPUT_DIR", "/tmp/srugati/outputs"))
MAX_UPLOAD_BYTES = 100 * 1024 * 1024

VIDEO_MEDIA_TYPES = {
    ".mp4": "video/mp4",
    ".mov": "video/quicktime",
    ".mkv": "video/x-matroska",
    ".webm": "video/webm",
    ".avi": "video/x-msvideo",
}

AUDIO_FORMATS = {
    # format name -> (extension, ffmpeg codec, media type)
    "m4a": ("m4a", "aac", "audio/mp4"),
    "mp3": ("mp3", "libmp3lame", "audio/mpeg"),
    "wav": ("wav", "pcm_s16le", "audio/wav"),
}

# Containers we'll remux a shifted video into on request — both are
# ISO-BMFF-family containers compatible with the h264/aac streams this
# pipeline produces, so it's a plain remux, no re-encode.
VIDEO_CONTAINERS = {"mp4": ".mp4", "mov": ".mov"}


def _ext_of(filename: str) -> str:
    return os.path.splitext(filename.lower())[1] or ".bin"


def _clean_name(name: str) -> str:
    base = os.path.splitext(os.path.basename(name))[0]
    return re.sub(r"[^A-Za-z0-9 _-]+", "", base).strip() or "track"


def _output_path(name: str) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    candidate = OUTPUT_DIR / name
    stem, suffix = candidate.stem, candidate.suffix
    i = 2
    while candidate.exists():
        candidate = OUTPUT_DIR / f"{stem}_{i}{suffix}"
        i += 1
    return candidate


def _delete_later(path: str) -> None:
    Path(path).unlink(missing_ok=True)


# Running jobs the app can cancel by id (X-Job-Id header + POST /jobs/{id}/cancel).
# A cancel that arrives before its job has started is remembered briefly.
_JOBS: dict[str, threading.Event] = {}
_EARLY_CANCELS: dict[str, float] = {}


async def _run_cancellable(request: Request, work):
    """
    Runs the blocking [work(cancel)] in a thread. The work is abandoned (ffmpeg
    killed, remaining steps skipped) if the app calls /jobs/{id}/cancel or the
    client connection drops.
    """
    cancel = threading.Event()
    job_id = request.headers.get("x-job-id")
    if job_id:
        _JOBS[job_id] = cancel
        now = time.time()
        for stale in [k for k, t in _EARLY_CANCELS.items() if now - t > 120]:
            _EARLY_CANCELS.pop(stale, None)
        if _EARLY_CANCELS.pop(job_id, None) is not None:
            cancel.set()

    async def watch():
        while not cancel.is_set():
            if await request.is_disconnected():
                print("client disconnected; cancelling job", job_id)
                cancel.set()
                return
            await asyncio.sleep(0.3)

    watcher = asyncio.create_task(watch())
    try:
        result = await asyncio.to_thread(work, cancel)
    finally:
        watcher.cancel()
        if job_id:
            _JOBS.pop(job_id, None)
    if cancel.is_set():
        raise audio.Cancelled()
    return result


@app.post("/jobs/{job_id}/cancel")
async def cancel_job(job_id: str):
    event = _JOBS.get(job_id)
    if event is not None:
        event.set()
        print("job cancelled by app:", job_id)
        return {"cancelled": True}
    _EARLY_CANCELS[job_id] = time.time()
    return {"cancelled": False, "queued": True}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/pitch/detect")
async def detect_pitch(request: Request, file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(400, "Missing filename")

    with tempfile.TemporaryDirectory() as tmp:
        in_path = os.path.join(tmp, f"{uuid.uuid4()}{_ext_of(file.filename)}")
        wav_path = os.path.join(tmp, f"{uuid.uuid4()}.wav")

        contents = await file.read()
        if not contents:
            raise HTTPException(400, "Empty file upload")
        if len(contents) > MAX_UPLOAD_BYTES:
            raise HTTPException(413, "This file is too large — the limit is 100MB.")
        Path(in_path).write_bytes(contents)

        def work(cancel):
            try:
                audio.decode_to_wav(in_path, wav_path, cancel)
            except audio.Cancelled:
                raise
            except Exception:
                raise HTTPException(400, "Could not read this file — try a different one.")
            if cancel.is_set():
                raise audio.Cancelled()
            result = pitch.detect(wav_path)
            if cancel.is_set():
                raise audio.Cancelled()
            try:
                result.update(pitch.analyze(wav_path))
            except Exception:
                pass
            return result

        try:
            return await _run_cancellable(request, work)
        except audio.Cancelled:
            print("pitch/detect cancelled by client")
            raise HTTPException(499, "Cancelled")


@app.post("/pitch/shift")
async def shift_pitch(
    request: Request,
    file: UploadFile = File(...),
    semitones: float = Form(0.0),
    tempo: float = Form(1.0),
    label: str = Form(""),
    preserve_formant: bool = Form(True),
    want: str = Form("auto"),
    output_format: str = Form("auto"),
):
    """
    want: "auto" (video in -> video out, audio in -> audio out — the
        original behaviour), "audio" (always return just the shifted
        audio track, even for a video upload), or "video" (video upload
        only — shifted audio remuxed back into the video).
    output_format: for want="audio", one of AUDIO_FORMATS ("m4a"/"mp3"/
        "wav", "auto" = m4a); for want="video"/"auto" video, one of
        VIDEO_CONTAINERS ("mp4"/"mov", "auto" = same container as the
        upload).
    """
    if not file.filename:
        raise HTTPException(400, "Missing filename")
    if not (-24.0 <= semitones <= 24.0):
        raise HTTPException(400, "semitones must be between -24 and 24")
    if not (0.5 <= tempo <= 2.0):
        raise HTTPException(400, "tempo must be between 0.5 and 2.0")
    if want not in ("auto", "audio", "video"):
        raise HTTPException(400, "want must be 'auto', 'audio', or 'video'")

    ext = _ext_of(file.filename)
    is_video_upload = ext in VIDEO_MEDIA_TYPES
    want_video = want == "video" or (want == "auto" and is_video_upload)
    if want_video and not is_video_upload:
        raise HTTPException(400, "want=video requires a video upload")

    if want_video:
        container_ext = VIDEO_CONTAINERS.get(output_format, ext) if output_format != "auto" else ext
    audio_format, audio_codec, audio_media_type = AUDIO_FORMATS.get(
        output_format if not want_video else "m4a", AUDIO_FORMATS["m4a"]
    )

    tag = re.sub(r"[^A-Za-z0-9]+", "", label) or "shifted"
    tempo_suffix = f"_{round(tempo * 100)}pct" if abs(tempo - 1.0) > 1e-6 else ""
    base_name = f"{tag}{tempo_suffix}_{_clean_name(file.filename)}"
    out_name = f"{base_name}{container_ext}" if want_video else f"{base_name}.{audio_format}"

    with tempfile.TemporaryDirectory() as tmp:
        in_path = os.path.join(tmp, f"{uuid.uuid4()}{ext}")
        contents = await file.read()
        if not contents:
            raise HTTPException(400, "Empty file upload")
        if len(contents) > MAX_UPLOAD_BYTES:
            raise HTTPException(413, "This file is too large — the limit is 100MB.")
        Path(in_path).write_bytes(contents)

        decoded_wav = os.path.join(tmp, f"{uuid.uuid4()}.wav")
        shifted_audio = os.path.join(tmp, f"{uuid.uuid4()}_shifted.{audio_format}")

        out_path = _output_path(out_name)

        def work(cancel):
            try:
                audio.decode_to_wav(in_path, decoded_wav, cancel)
                audio.shift_pitch_tempo(
                    decoded_wav, shifted_audio, semitones, tempo, preserve_formant, codec=audio_codec, cancel=cancel
                )
            except audio.Cancelled:
                raise
            except Exception:
                raise HTTPException(400, "Could not process this file — try a different one.")

            if want_video:
                try:
                    audio.replace_audio_track(in_path, shifted_audio, str(out_path), cancel)
                except audio.Cancelled:
                    raise
                except Exception:
                    raise HTTPException(500, "Could not rebuild the video with the shifted audio.")
            else:
                Path(shifted_audio).rename(out_path)

        try:
            await _run_cancellable(request, work)
        except audio.Cancelled:
            Path(out_path).unlink(missing_ok=True)
            print("pitch/shift cancelled by client")
            raise HTTPException(499, "Cancelled")

        media_type = VIDEO_MEDIA_TYPES.get(container_ext, "video/mp4") if want_video else audio_media_type

        return FileResponse(
            path=str(out_path),
            media_type=media_type,
            filename=out_name,
            background=BackgroundTask(_delete_later, str(out_path)),
        )


@app.post("/pitch/mix")
async def mix_take(
    request: Request,
    track: UploadFile = File(...),
    vocal: UploadFile = File(...),
    semitones: float = Form(0.0),
    tempo: float = Form(1.0),
    vocal_delay_sec: float = Form(0.0),
    vocal_gain: float = Form(1.0),
    track_gain: float = Form(0.8),
    label: str = Form("mix"),
):
    """Mixes a vocal take recorded on the phone with the backing track (shifted
    to the pitch/tempo the singer used) and returns one m4a."""
    if not track.filename or not vocal.filename:
        raise HTTPException(400, "Missing filename")
    if not (-24.0 <= semitones <= 24.0):
        raise HTTPException(400, "semitones must be between -24 and 24")
    if not (0.5 <= tempo <= 2.0):
        raise HTTPException(400, "tempo must be between 0.5 and 2.0")
    if not (0.0 <= vocal_delay_sec <= 3600):
        raise HTTPException(400, "vocal_delay_sec out of range")
    vocal_gain = min(max(vocal_gain, 0.0), 3.0)
    track_gain = min(max(track_gain, 0.0), 3.0)

    out_name = f"{re.sub(r'[^A-Za-z0-9]+', '', label) or 'mix'}_{_clean_name(Path(track.filename).stem)}.m4a"
    with tempfile.TemporaryDirectory() as tmp:
        track_path = os.path.join(tmp, f"{uuid.uuid4()}{_ext_of(track.filename)}")
        vocal_path = os.path.join(tmp, f"{uuid.uuid4()}{_ext_of(vocal.filename)}")
        track_bytes = await track.read()
        vocal_bytes = await vocal.read()
        if not track_bytes or not vocal_bytes:
            raise HTTPException(400, "Empty file upload")
        if len(track_bytes) > MAX_UPLOAD_BYTES or len(vocal_bytes) > MAX_UPLOAD_BYTES:
            raise HTTPException(413, "This file is too large — the limit is 100MB.")
        Path(track_path).write_bytes(track_bytes)
        Path(vocal_path).write_bytes(vocal_bytes)
        out_path = _output_path(out_name)

        def work(cancel):
            try:
                audio.mix_vocal_with_track(
                    track_path, vocal_path, str(out_path), semitones, tempo,
                    vocal_delay_sec, vocal_gain, track_gain, cancel=cancel,
                )
            except audio.Cancelled:
                raise
            except Exception:
                raise HTTPException(400, "Could not mix these files — try again.")

        try:
            await _run_cancellable(request, work)
        except audio.Cancelled:
            Path(out_path).unlink(missing_ok=True)
            raise HTTPException(499, "Cancelled")

        return FileResponse(
            path=str(out_path),
            media_type="audio/mp4",
            filename=out_name,
            background=BackgroundTask(_delete_later, str(out_path)),
        )
