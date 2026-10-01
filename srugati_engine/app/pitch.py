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
