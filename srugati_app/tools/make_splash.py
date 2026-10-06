"""Rebuilds assets/srugati1.mp4 from the original black-background splash:
 - background -> app navy, music notes -> soft violet, logo -> solid app violet (#9A8CFF)
 - the G's drum ring becomes a tabla (laced bowl + dark syahi spot)
Usage: python3 make_splash.py ORIGINAL.mp4 OUT.mp4 [--preview frame_no]
"""
import subprocess, sys, os, tempfile, glob
import numpy as np
from PIL import Image, ImageDraw

BG = np.array([10, 14, 42], float)
NOTE = np.array([92, 82, 189], float)          # colour of mid-grey notes
C_LEFT = np.array([154, 140, 255], float)       # violet
C_RIGHT = np.array([154, 140, 255], float)      # same violet: the logo is one solid colour
LOGO_X0, LOGO_X1 = 95, 971
CX, CY = 587.5, 985.0                           # centre of the G's ring
SS = 4                                          # supersampling for the tabla art

def tabla_layers(w, h):
    """Returns (white_details, clear_mask) float masks (0..1) for the tabla drawn inside the G's ring."""
    box = 200
    x0, y0 = int(CX - box / 2), int(CY - box / 2)
    big = box * SS
    s = SS
    c = big / 2
    white = Image.new("L", (big, big), 0)
    clear = Image.new("L", (big, big), 0)
    dw, dc = ImageDraw.Draw(white), ImageDraw.Draw(clear)
    # wipe the old centre dot
    dc.ellipse([c - 32 * s, c - 32 * s, c + 32 * s, c + 32 * s], fill=255)
    # drum head: elliptical outline, solid syahi spot in the middle
    hx, hy, rx, ry = c, c - 15 * s, 38 * s, 15 * s
    dw.ellipse([hx - rx, hy - ry, hx + rx, hy + ry], outline=255, width=int(4 * s))
    dw.ellipse([hx - 17 * s, hy - 7 * s, hx + 17 * s, hy + 7 * s], fill=255)
    # laced bowl: curved straps from the head's lower rim down to the base
    n = 7
    for k in range(-3, 4):
        u = k / 3.0
        tx = hx + u * (rx - 3 * s)
        ty = hy + ry * np.sqrt(max(1 - u * u, 0))
        bx = hx + u * 20 * s                       # straps converge toward the base
        by = c + 48 * s
        mx = hx + u * (rx - 2 * s) * 0.95
        my = (ty + by) / 2
        pts = []
        for q in np.linspace(0, 1, 30):
            xq = (1 - q) ** 2 * tx + 2 * (1 - q) * q * mx + q ** 2 * bx
            yq = (1 - q) ** 2 * ty + 2 * (1 - q) * q * my + q ** 2 * by
            pts.append((xq, yq))
        dw.line(pts, fill=255, width=int(3.4 * s))
    # base band
    dw.line([(c - 22 * s, c + 47 * s), (c + 22 * s, c + 47 * s)], fill=255, width=int(4 * s))
    # keep everything inside the ring's inner edge
    yy, xx = np.mgrid[0:big, 0:big]
    inside = (np.hypot(xx - c, yy - c) < 50.5 * s)
    wmask = np.array(white, float) / 255 * inside
    cmask = np.array(clear, float) / 255
    wmask = np.array(Image.fromarray((wmask * 255).astype(np.uint8)).resize((box, box), Image.LANCZOS), float) / 255
    cmask = np.array(Image.fromarray((cmask * 255).astype(np.uint8)).resize((box, box), Image.LANCZOS), float) / 255
    W = np.zeros((h, w)); C = np.zeros((h, w))
    W[y0:y0 + box, x0:x0 + box] = wmask
    C[y0:y0 + box, x0:x0 + box] = cmask
    return W, C

def process(frame, W, B, ring_cov, xx):
    L = np.array(frame.convert("L"), float) / 255
    L = L * (1 - B * ring_cov)                    # wipe the old centre dot
    L = np.maximum(L, W * ring_cov)               # draw the tabla
    t = np.clip((xx - LOGO_X0) / (LOGO_X1 - LOGO_X0), 0, 1)[..., None]
    logo = C_LEFT * (1 - t) + C_RIGHT * t
    L3 = L[..., None]
    low = BG + (NOTE - BG) * np.clip(L3 / 0.5, 0, 1)
    high = NOTE + (logo - NOTE) * np.clip((L3 - 0.5) / 0.5, 0, 1)
    out = np.where(L3 <= 0.5, low, high)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))

def main():
    src, dst = sys.argv[1], sys.argv[2]
    preview = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == "--preview" else None
    tmp = tempfile.mkdtemp()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, f"{tmp}/f_%03d.png"], check=True)
    frames = sorted(glob.glob(f"{tmp}/f_*.png"))
    first = Image.open(frames[0]); w, h = first.size
    W, B = tabla_layers(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - CX, yy - CY)
    ring = (r > 58) & (r < 80)
    final = np.array(Image.open(frames[-1]).convert("L"), float)[ring].mean()
    os.makedirs(f"{tmp}/out", exist_ok=True)
    for i, f in enumerate(frames, 1):
        if preview and i != preview: continue
        im = Image.open(f)
        cov = np.clip(np.array(im.convert("L"), float)[ring].mean() / final, 0, 1)
        cov = 0.0 if cov < 0.6 else cov            # details only once the ring has drawn in
        out = process(im, W, B, cov, xx)
        if preview:
            out.save(dst); return
        out.save(f"{tmp}/out/o_{i:03d}.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", f"{tmp}/out/o_%03d.png",
                    "-i", src, "-map", "0:v", "-map", "1:a?", "-c:v", "libx264", "-crf", "18", "-preset", "slow",
                    "-pix_fmt", "yuv420p", "-c:a", "copy", "-shortest", dst], check=True)

if __name__ == "__main__":
    main()
