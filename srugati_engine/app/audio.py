"""ffmpeg helpers: decode any audio/video to WAV, and independent pitch/tempo shift."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

FFMPEG_PATH = os.getenv("SRUGATI_FFMPEG_PATH", "/usr/bin/ffmpeg")
SAMPLE_RATE = int(os.getenv("SRUGATI_SAMPLE_RATE", "48000"))
CHANNELS = int(os.getenv("SRUGATI_CHANNELS", "1"))


def _run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, capture_output=True)


def decode_to_wav(input_path: str, wav_path: str) -> None:
    """Decode any ffmpeg-readable audio or video file down to a WAV (audio only)."""
    _run([
        FFMPEG_PATH, "-y", "-hide_banner", "-loglevel", "error",
        "-i", input_path,
        "-vn", "-ac", str(CHANNELS), "-ar", str(SAMPLE_RATE),
        wav_path,
    ])
    if not Path(wav_path).exists():
        raise RuntimeError("Decode produced no output")


def shift_pitch_tempo(
    input_wav: str,
    output_audio: str,
    semitones: float,
    tempo: float,
    preserve_formant: bool = True,
    codec: str = "aac",
) -> None:
    """
    Independently pitch-shift and/or time-stretch a WAV via ffmpeg's rubberband filter
    (the real Rubber Band library, not a lightweight reimplementation).
      pitch_ratio = 2^(semitones/12)   (1.0 == unchanged pitch)
      tempo        = duration ratio     (1.0 == unchanged speed)
      preserve_formant = keep a shifted voice's timbre natural (Rubber Band's
        mature `formant=preserved` option) instead of letting formants shift
        with pitch ("chipmunk"/"monster"). This is the library's own built-in
        handling, not a reimplementation — much more tested on full music
        mixes than a from-scratch formant estimator would be.
      codec = "aac" (default, compressed — safely under Cloud Run's ~32MB
        response cap for a typical song), "libmp3lame", or "pcm_s16le" (WAV
        is uncompressed — a several-minute-long track can exceed that cap).
    """
    pitch_ratio = 2 ** (semitones / 12.0)
    formant = "preserved" if preserve_formant else "shifted"
    codec_args = ["-c:a", codec]
    if codec in ("aac", "libmp3lame"):
        codec_args += ["-b:a", "192k"]
    _run([
        FFMPEG_PATH, "-y", "-hide_banner", "-loglevel", "error",
        "-i", input_wav,
        "-filter:a", f"rubberband=pitch={pitch_ratio}:tempo={tempo}:formant={formant}",
        "-ac", str(CHANNELS), "-ar", str(SAMPLE_RATE),
        *codec_args,
        output_audio,
    ])
    if not Path(output_audio).exists():
        raise RuntimeError("Shift produced no output")


def replace_audio_track(original_media: str, new_audio_wav: str, output_media: str) -> None:
    """Replace a video's audio track with new_audio_wav, keeping the video stream untouched."""
    _run([
        FFMPEG_PATH, "-y", "-hide_banner", "-loglevel", "error",
        "-i", original_media,
        "-i", new_audio_wav,
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "copy", "-c:a", "aac", "-shortest",
        output_media,
    ])
    if not Path(output_media).exists():
        raise RuntimeError("Mux produced no output")
