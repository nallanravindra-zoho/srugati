"""ffmpeg helpers: decode any audio/video to WAV, and independent pitch/tempo shift."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

FFMPEG_PATH = os.getenv("SRUGATI_FFMPEG_PATH", "/usr/bin/ffmpeg")
SAMPLE_RATE = int(os.getenv("SRUGATI_SAMPLE_RATE", "48000"))
CHANNELS = int(os.getenv("SRUGATI_CHANNELS", "1"))


class Cancelled(Exception):
    """The client went away mid-request; the work was abandoned."""


def _run(cmd: list[str], cancel=None) -> None:
    if cancel is None:
        subprocess.run(cmd, check=True, capture_output=True)
        return
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    while True:
        try:
            proc.wait(timeout=0.25)
            break
        except subprocess.TimeoutExpired:
            if cancel.is_set():
                proc.kill()
                proc.wait()
                raise Cancelled()
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, stderr=proc.stderr.read())


def decode_to_wav(input_path: str, wav_path: str, cancel=None) -> None:
    """Decode any ffmpeg-readable audio or video file down to a WAV (audio only)."""
    _run([
        FFMPEG_PATH, "-y", "-hide_banner", "-loglevel", "error",
        "-i", input_path,
        "-vn", "-ac", str(CHANNELS), "-ar", str(SAMPLE_RATE),
        wav_path,
    ], cancel)
    if not Path(wav_path).exists():
        raise RuntimeError("Decode produced no output")


def shift_pitch_tempo(
    input_wav: str,
    output_audio: str,
    semitones: float,
    tempo: float,
    preserve_formant: bool = True,
    codec: str = "aac",
    cancel=None,
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
    ], cancel)
    if not Path(output_audio).exists():
        raise RuntimeError("Shift produced no output")


def replace_audio_track(original_media: str, new_audio_wav: str, output_media: str, cancel=None) -> None:
    """Replace a video's audio track with new_audio_wav, keeping the video stream untouched."""
    _run([
        FFMPEG_PATH, "-y", "-hide_banner", "-loglevel", "error",
        "-i", original_media,
        "-i", new_audio_wav,
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "copy", "-c:a", "aac", "-shortest",
        output_media,
    ], cancel)
    if not Path(output_media).exists():
        raise RuntimeError("Mux produced no output")


def mix_vocal_with_track(
    track_path: str,
    vocal_path: str,
    output_audio: str,
    semitones: float,
    tempo: float,
    vocal_delay_sec: float,
    vocal_gain: float,
    track_gain: float,
    codec: str = "aac",
    cancel=None,
) -> None:
    """
    Mix a recorded vocal take over a backing track. The track gets the same
    pitch/tempo the singer practised at; the vocal (recorded in real time) is
    delayed so it lines up with where the song was when recording began.
    """
    pitch_ratio = 2 ** (semitones / 12.0)
    delay_ms = max(0, int(round(vocal_delay_sec * 1000)))
    # A negative delay means the vocal must start before the track does:
    # cut that much off the front of the take instead.
    trim_sec = max(0.0, -vocal_delay_sec)
    track_chain = f"[0:a]aformat=channel_layouts=stereo,aresample={SAMPLE_RATE}"
    if abs(semitones) > 1e-6 or abs(tempo - 1.0) > 1e-6:
        track_chain += f",rubberband=pitch={pitch_ratio}:tempo={tempo}:formant=preserved"
    track_chain += f",volume={track_gain}[t]"
    vocal_chain = (
        f"[1:a]aformat=channel_layouts=stereo,aresample={SAMPLE_RATE},"
        + (f"atrim=start={trim_sec},asetpts=PTS-STARTPTS," if trim_sec > 0 else "")
        + f"adelay={delay_ms}|{delay_ms},volume={vocal_gain}[v]"
    )
    graph = f"{track_chain};{vocal_chain};[t][v]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.97[o]"
    codec_args = ["-c:a", codec]
    if codec in ("aac", "libmp3lame"):
        codec_args += ["-b:a", "192k"]
    _run([
        FFMPEG_PATH, "-y", "-hide_banner", "-loglevel", "error",
        "-i", track_path, "-i", vocal_path,
        "-filter_complex", graph, "-map", "[o]",
        "-ar", str(SAMPLE_RATE),
        *codec_args,
        output_audio,
    ], cancel)
    if not Path(output_audio).exists():
        raise RuntimeError("Mix produced no output")
