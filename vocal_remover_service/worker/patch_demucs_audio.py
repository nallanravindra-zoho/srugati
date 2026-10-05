# Run at Docker build time. demucs.audio.save_audio() writes .wav/.flac via
# torchaudio.save(), which depends on torchcodec — whose native library
# fails to load on this base image (FFmpeg ABI mismatch). Append a
# replacement save_audio() that writes via soundfile instead; Python keeps
# the last definition of a name in a module, so this shadows the original
# for every caller that does `from .audio import save_audio`.
import shutil
from pathlib import Path

import demucs.audio

patch = '''

# --- Patched at Docker build time: bypass torchaudio.save (requires
# torchcodec, whose native library fails to load here) in favor of
# soundfile, which writes wav/flac directly. ---
import soundfile as _sf


def save_audio(wav, path, samplerate, bitrate=320, clip="rescale",
               bits_per_sample=16, as_float=False, preset=2):
    wav = prevent_clip(wav, mode=clip)
    path = Path(path)
    suffix = path.suffix.lower()
    if suffix == ".mp3":
        encode_mp3(wav, path, samplerate, bitrate, preset, verbose=True)
        return
    data = wav.detach().cpu().numpy().T
    subtype = "FLOAT" if as_float else {
        16: "PCM_16", 24: "PCM_24", 32: "PCM_32",
    }.get(bits_per_sample, "PCM_16")
    _sf.write(str(path), data, samplerate, subtype=subtype)
'''

with open(demucs.audio.__file__, "a") as f:
    f.write(patch)

# The `import demucs.audio` above compiled and cached the pre-patch source
# as a .pyc. If the append happens within the same filesystem mtime
# resolution window (a real risk with some container overlay filesystems),
# Python's staleness check won't notice the file changed and will keep
# using the stale, unpatched bytecode at runtime. Force a clean recompile.
cache_dir = Path(demucs.audio.__file__).parent / "__pycache__"
if cache_dir.exists():
    shutil.rmtree(cache_dir)

print(f"Patched {demucs.audio.__file__}, cleared {cache_dir}")
