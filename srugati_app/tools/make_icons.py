"""Generates the app icon (full SruGati wordmark on navy) for Android and iOS from the final frame
of assets/srugati1.mp4.  Usage: python3 tools/make_icons.py   (run from srugati_app/)
Android: legacy rounded PNGs + adaptive icon (navy background, wordmark foreground)
iOS: every size in AppIcon.appiconset, full-bleed (iOS rounds the corners itself)
"""
import json, os, subprocess, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

NAVY = np.array([10, 14, 42])
VIOLET = np.array([178, 166, 255])   # a touch lighter than the in-app violet for contrast on a small icon
BOLD = 5                      # stroke thickening, in source pixels (odd number)
RES = "android/app/src/main/res"
APPICON = "ios/Runner/Assets.xcassets/AppIcon.appiconset"


def wordmark():
    tmp = tempfile.mkdtemp()
    frame = f"{tmp}/f.png"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-sseof", "-0.3", "-i", "assets/srugati1.mp4",
                    "-frames:v", "1", frame], check=True)
    a = np.array(Image.open(frame).convert("RGB")).astype(float)
    t = np.clip(a[..., 0] / (0.85 * 255), 0, 1)                 # the video is a grey brightness map: 0 = background, 0.85 grey = logo
    alpha = np.clip((t - 0.10) / 0.22, 0, 1)
    x0, y0, x1, y1 = 80, 700, 1000, 1230
    al, tn = alpha[y0:y1, x0:x1], t[y0:y1, x0:x1]
    ys, xs = np.where(al > 0.15)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    al = al[box[1]:box[3], box[0]:box[2]]
    tn = tn[box[1]:box[3], box[0]:box[2]]
    # Bolder: thicken every stroke (the thin staff line and veena outline especially).
    al_img = Image.fromarray((al * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(BOLD))
    tn_img = Image.fromarray((tn * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(BOLD))
    tn = np.clip(np.array(tn_img).astype(float) / 255, 0, 1) ** 0.8
    rgb = NAVY + (VIOLET - NAVY) * tn[..., None]               # keeps the tabla's two-tone shading
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)), al_img.filter(ImageFilter.GaussianBlur(0.8))


def compose(size, width_frac, background=True, rounded=False):
    rgb, al = wordmark()
    w = int(size * width_frac)
    h = int(al.height * w / al.width)
    rgb, al = rgb.resize((w, h), Image.LANCZOS), al.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), tuple(NAVY) + (255,) if background else (0, 0, 0, 0))
    canvas.paste(rgb, ((size - w) // 2, (size - h) // 2), al)
    if rounded:
        m = Image.new("L", (size, size), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.23), fill=255)
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.paste(canvas, (0, 0), m)
        return out
    return canvas


def android():
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for d, px in densities.items():
        os.makedirs(f"{RES}/mipmap-{d}", exist_ok=True)
        compose(px * 4, 0.90, rounded=True).resize((px, px), Image.LANCZOS).save(f"{RES}/mipmap-{d}/ic_launcher.png")
        fg = int(px * 108 / 48)
        compose(fg * 4, 0.64, background=False).resize((fg, fg), Image.LANCZOS).save(
            f"{RES}/mipmap-{d}/ic_launcher_foreground.png")
    os.makedirs(f"{RES}/mipmap-anydpi-v26", exist_ok=True)
    open(f"{RES}/mipmap-anydpi-v26/ic_launcher.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n')
    open(f"{RES}/values/ic_launcher_background.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#0A0E2A</color>\n</resources>\n')


def ios():
    master = compose(2048, 0.90)
    contents = json.load(open(f"{APPICON}/Contents.json"))
    for img in contents["images"]:
        size = float(img["size"].split("x")[0])
        px = int(round(size * int(img["scale"].rstrip("x"))))
        master.convert("RGB").resize((px, px), Image.LANCZOS).save(f"{APPICON}/{img['filename']}")


if __name__ == "__main__":
    android()
    ios()
    print("icons written")
