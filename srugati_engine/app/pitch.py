"""Pitch detection: WAV -> (frequency, note name, octave, cents, confidence)."""
from __future__ import annotations

import numpy as np
import aubio

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

HOP_SIZE = 2048
WIN_SIZE = 8192
PITCH_METHOD = "yin"
SILENCE_DB = -40.0
MIN_HZ = 50.0
MAX_HZ = 1500.0
MIN_CONFIDENCE = 0.6
MAX_ANALYZE_SECONDS = 45.0


def hz_to_note(hz: float) -> dict:
    midi_float = 69 + 12 * np.log2(hz / 440.0)
    midi = int(round(midi_float))
    cents = float((midi_float - midi) * 100.0)
    name = NOTE_NAMES[(midi + 12) % 12]
    octave = (midi // 12) - 1
    return {"note": name, "octave": octave, "midi": midi, "cents": cents}


def detect(wav_path: str) -> dict:
    source = aubio.source(wav_path, 0, HOP_SIZE)
    sample_rate = source.samplerate

    detector = aubio.pitch(PITCH_METHOD, WIN_SIZE, HOP_SIZE, sample_rate)
    detector.set_unit("Hz")
    detector.set_silence(SILENCE_DB)

    max_frames = int((MAX_ANALYZE_SECONDS * sample_rate) / HOP_SIZE)

    frequencies: list[float] = []
    confidences: list[float] = []
    frames = 0

    while True:
        samples, read = source()
        if read == 0:
            break

        hz = float(detector(samples)[0])
        confidence = float(detector.get_confidence())

        if confidence >= MIN_CONFIDENCE and MIN_HZ <= hz <= MAX_HZ:
            frequencies.append(hz)
            confidences.append(confidence)

        frames += 1
        if frames >= max_frames:
            break

    if not frequencies:
        return {"frequencyHz": None, "confidence": 0.0, "note": None, "octave": None, "cents": None}

    frequency = float(np.median(frequencies))
    confidence = float(np.median(confidences))
    return {"frequencyHz": frequency, "confidence": confidence, **hz_to_note(frequency)}


WAVEFORM_BARS = 160
BPM_MIN, BPM_MAX = 60.0, 180.0
MAJOR_PROFILE = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR_PROFILE = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])


def _waveform(samples: np.ndarray) -> list[float]:
    if samples.size == 0:
        return []
    buckets = np.array_split(np.abs(samples), WAVEFORM_BARS)
    peaks = np.array([b.max() if b.size else 0.0 for b in buckets])
    top = peaks.max()
    if top <= 0:
        return [0.0] * WAVEFORM_BARS
    return [round(float(v), 3) for v in np.sqrt(peaks / top)]


def _bpm(wav_path: str) -> float | None:
    hop, win = 512, 1024
    source = aubio.source(wav_path, 0, hop)
    tempo = aubio.tempo("default", win, hop, source.samplerate)
    max_frames = int(90 * source.samplerate / hop)
    frames = 0
    while frames < max_frames:
        samples, read = source()
        if read == 0:
            break
        tempo(samples)
        frames += 1
    bpm = float(tempo.get_bpm())
    if bpm <= 0:
        return None
    while bpm < BPM_MIN:
        bpm *= 2
    while bpm > BPM_MAX:
        bpm /= 2
    return round(bpm, 1)


def _key(samples: np.ndarray, sample_rate: int) -> dict | None:
    frame = 8192
    if samples.size < frame * 4:
        return None
    mid = samples.size // 2
    span = min(samples.size, sample_rate * 60)
    clip = samples[max(0, mid - span // 2): mid + span // 2]

    freqs = np.fft.rfftfreq(frame, 1.0 / sample_rate)
    usable = (freqs >= 65.0) & (freqs <= 2000.0)
    pitch_class = (np.round(12 * np.log2(freqs[usable] / 440.0) + 69).astype(int)) % 12
    window = np.hanning(frame)

    chroma = np.zeros(12)
    for start in range(0, clip.size - frame, frame // 2):
        mag = np.abs(np.fft.rfft(clip[start:start + frame] * window))[usable]
        np.add.at(chroma, pitch_class, np.sqrt(mag))
    if chroma.sum() <= 0:
        return None

    best = (-2.0, 0, "major")
    for tonic in range(12):
        rolled = np.roll(chroma, -tonic)
        for mode, profile in (("major", MAJOR_PROFILE), ("minor", MINOR_PROFILE)):
            r = float(np.corrcoef(rolled, profile)[0, 1])
            if r > best[0]:
                best = (r, tonic, mode)
    return {"tonic": NOTE_NAMES[best[1]], "mode": best[2], "confidence": round(max(0.0, best[0]), 3)}


def analyze(wav_path: str) -> dict:
    """Whole-track extras for the player: duration, waveform peaks, BPM and key."""
    import soundfile as sf

    samples, sample_rate = sf.read(wav_path, dtype="float32", always_2d=False)
    if samples.ndim > 1:
        samples = samples.mean(axis=1)

    result: dict = {
        "durationSec": round(float(samples.size / sample_rate), 2),
        "waveform": _waveform(samples),
        "bpm": None,
        "key": None,
    }
    try:
        result["bpm"] = _bpm(wav_path)
    except Exception:
        pass
    try:
        result["key"] = _key(samples, sample_rate)
    except Exception:
        pass
    return result
