"""SruGati Engine — pitch detection + independent pitch/tempo shifting for any audio or video file."""
from __future__ import annotations

import os
import re
import tempfile
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


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/pitch/detect")
async def detect_pitch(file: UploadFile = File(...)):
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

        try:
            audio.decode_to_wav(in_path, wav_path)
        except Exception:
            raise HTTPException(400, "Could not read this file — try a different one.")

        result = pitch.detect(wav_path)
        try:
            result.update(pitch.analyze(wav_path))
        except Exception:
            pass
        return result


@app.post("/pitch/shift")
async def shift_pitch(
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

        try:
            audio.decode_to_wav(in_path, decoded_wav)
            audio.shift_pitch_tempo(
                decoded_wav, shifted_audio, semitones, tempo, preserve_formant, codec=audio_codec
            )
        except Exception:
            raise HTTPException(400, "Could not process this file — try a different one.")

        out_path = _output_path(out_name)

        if want_video:
            try:
                audio.replace_audio_track(in_path, shifted_audio, str(out_path))
            except Exception:
                raise HTTPException(500, "Could not rebuild the video with the shifted audio.")
            media_type = VIDEO_MEDIA_TYPES.get(container_ext, "video/mp4")
        else:
            Path(shifted_audio).rename(out_path)
            media_type = audio_media_type

        return FileResponse(
            path=str(out_path),
            media_type=media_type,
            filename=out_name,
            background=BackgroundTask(_delete_later, str(out_path)),
        )
