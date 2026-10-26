"""Runs each model in MODELS on INPUT_URI (gs://...), twice (cold, then warm), uploads the stems and
prints a JSON timing summary. Used only to evaluate RoFormer models on a GPU."""
import json, os, time, shutil
import torch
from google.cloud import storage
from audio_separator.separator import Separator

INPUT_URI = os.environ["INPUT_URI"]
OUT_PREFIX = os.environ.get("OUTPUT_PREFIX", "gs://srugati-app-outputs/test").rstrip("/")
MODELS = [m for m in os.environ.get("MODELS", "model_bs_roformer_ep_317_sdr_12.9755.ckpt,vocals_mel_band_roformer.ckpt").split(",") if m]
client = storage.Client()

def split(uri):
    bucket, path = uri[5:].split("/", 1)
    return client.bucket(bucket), path

os.makedirs("/tmp/in", exist_ok=True)
local = "/tmp/in/" + os.path.basename(INPUT_URI)
b, path = split(INPUT_URI)
b.blob(path).download_to_filename(local)
print("input", local, os.path.getsize(local), "bytes", flush=True)
print("cuda available:", torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else "-", "| cpus:", os.cpu_count(), flush=True)

results = []
for m in MODELS:
    tag = m.split(".")[0]
    out_dir = f"/tmp/out/{tag}"
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    entry = {"model": m}
    try:
        t0 = time.time()
        sep = Separator(output_dir=out_dir, model_file_dir="/tmp/models", output_format="WAV")
        sep.load_model(model_filename=m)
        entry["load_s"] = round(time.time() - t0, 1)
        for label in ("cold_run_s", "warm_run_s")[: int(os.environ.get("RUNS", "2"))]:
            t = time.time()
            files = sep.separate(local)
            entry[label] = round(time.time() - t, 1)
            print(m, label, entry[label], files, flush=True)
        ob, oprefix = split(OUT_PREFIX + "/" + tag + "/x")
        oprefix = oprefix[:-2]
        entry["outputs"] = []
        for f in os.listdir(out_dir):
            ob.blob(f"{oprefix}/{f}").upload_from_filename(os.path.join(out_dir, f))
            entry["outputs"].append(f"{OUT_PREFIX}/{tag}/{f}")
        del sep
        torch.cuda.empty_cache()
    except Exception as e:
        entry["error"] = repr(e)
        print("FAILED", m, repr(e), flush=True)
    results.append(entry)

print("RESULT " + json.dumps(results), flush=True)
