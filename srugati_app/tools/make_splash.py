"""Rebuilds assets/srugati1.mp4 from the original black-background splash:
 - background -> app navy, music notes -> soft violet, logo -> solid app violet (#9A8CFF)
 - the G's thick circle becomes a tabla: the circle is the head's gajra (braided rim), the maidan and
   syahi sit inside it, and the bowl with its straps hangs below (the S-strokes join at its top and bottom)
 - the flame above the "i" flickers like a candle (sway, stretch, glow, bright core), and the video is
   extended a couple of seconds so the flame can burn after the logo has formed
Usage: python3 make_splash.py ORIGINAL.mp4 OUT.mp4 [--preview frame_no]   (frame_no may exceed the
       original frame count to preview the extended, flame-only tail)
"""
import subprocess, sys, os, tempfile, glob
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

BG = np.array([10, 14, 42], float)
NOTE = np.array([92, 82, 189], float)          # colour of mid-grey notes
LOGO = np.array([154, 140, 255], float)         # solid app violet
CORE = np.array([236, 232, 255], float)         # bright centre of the flame
CX, CY = 587.5, 985.0                           # centre of the G's original ring
R_CLEAR = 81.0                                  # the whole original ring is replaced by the tabla
SS = 4                                          # supersampling for the tabla art
TILT_DEG = 8.0                                 # the whole tabla leans left (head toward the "U"), pivoting on its base
SHIFT_X = 10                                     # nudge right to keep clear of the U
EXTRA_FRAMES = 36                               # extra ~1.2 s of burning flame after the original ends
FPS = 30

# flame (the leaf above the "i")
FX0, FX1, FY0, FY1 = 928, 990, 826, 909         # warp rectangle
FBASE = 906.0                                   # row where the flame joins its holder (does not move)
FCX, FCY = 952.0, 872.0                         # glow centre


def tabla_layers(w, h):
    """((tone, alpha), clear): tone is a luminance layer (0..1), alpha where it is drawn, clear the disc to wipe."""
    box = 280
    x0, y0 = int(CX - box / 2) + SHIFT_X, int(CY - box / 2)
    big = box * SS
    s = SS
    c = big / 2
    tone = Image.new("L", (big, big), 0)
    cover = Image.new("L", (big, big), 0)
    clear = Image.new("L", (big, big), 0)
    dt, dv, dc = ImageDraw.Draw(tone), ImageDraw.Draw(cover), ImageDraw.Draw(clear)
    dc.ellipse([c - R_CLEAR * s - SHIFT_X * s, c - R_CLEAR * s, c + R_CLEAR * s - SHIFT_X * s, c + R_CLEAR * s], fill=255)

    def draw(fill_l, fn):
        fn(dt, fill_l); fn(dv, 255)

    A = 77.0                       # half width of head and bowl
    top_y = -77.0                  # head top, relative to the ring centre
    bot_y = 77.0                   # bowl bottom
    RY = 44.0                      # head ellipse half-height: the drum is tipped toward the viewer, so more head shows
    hy = top_y + RY                # head centre (relative)
    B = bot_y - hy                 # bowl depth below the head's centre
    N = 2.6                        # superellipse exponent: round bowl with a flat-ish base
    RIM = 15.0                     # gajra thickness

    def P(x, y):                   # relative -> big-canvas pixels
        return (c + x * s, c + y * s)

    # bowl silhouette (lower half of a superellipse), drawn as a filled body plus a thick outline
    pts = []
    for phi in np.linspace(0, np.pi, 90):
        cx_, sy_ = np.cos(phi), np.sin(phi)
        x = A * np.sign(cx_) * abs(cx_) ** (2 / N)
        y = hy + B * abs(sy_) ** (2 / N)
        pts.append(P(x, y))
    body = [P(-A, hy)] + pts + [P(A, hy)]
    draw(60, lambda d, f: d.polygon(body, fill=f))                       # dim bowl
    draw(255, lambda d, f: d.line(pts, fill=f, width=int(RIM * s), joint="curve"))   # bowl outline
    for end, inward in ((pts[0], -1), (pts[-1], 1)):                      # round the line ends, kept flush with the rim
        ex = end[0] + inward * 5.5 * s
        draw(255, lambda d, f, ex=ex, ey=end[1]: d.ellipse([ex - RIM * s / 2, ey - RIM * s / 2, ex + RIM * s / 2, ey + RIM * s / 2], fill=f))
    # straps: from the head's lower edge down the bowl, converging slightly with a gentle bulge
    for k in range(-3, 4):
        xt = k * 18.0
        yt = hy + RY * np.sqrt(max(1 - (xt / A) ** 2, 0)) - 2
        xb = k * 11.5
        yb = hy + B * max(1 - abs(xb / A) ** N, 0) ** (1 / N) - 6
        line = []
        for q in np.linspace(0, 1, 40):
            x = xt + (xb - xt) * q + k * 2.2 * 4 * q * (1 - q)
            y = yt + (yb - yt) * q
            line.append(P(x, y))
        draw(255, lambda d, f, line=line: d.line(line, fill=f, width=int(5.6 * s)))
    # head: gajra rim (outer ellipse), maidan skin inside, syahi disc in the middle
    draw(255, lambda d, f: d.ellipse([P(-A, hy - RY), P(A, hy + RY)], fill=f))
    draw(150, lambda d, f: d.ellipse([P(-(A - RIM), hy - (RY - RIM * 0.62)), P(A - RIM, hy + (RY - RIM * 0.62))], fill=f))
    draw(0, lambda d, f: d.ellipse([P(-30, hy - 11.5), P(30, hy + 11.5)], fill=f))

    # lean the whole tabla left about the centre of its base so the tail still leaves from the bottom
    pivot = (c, c + bot_y * s)
    tone = tone.rotate(TILT_DEG, resample=Image.BICUBIC, center=pivot)
    cover = cover.rotate(TILT_DEG, resample=Image.BICUBIC, center=pivot)

    def down(a):
        return np.array(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).resize((box, box), Image.LANCZOS), float) / 255
    tn = np.array(tone, float) / 255
    cv = np.array(cover, float) / 255
    T = np.zeros((h, w)); V = np.zeros((h, w)); C = np.zeros((h, w))
    T[y0:y0 + box, x0:x0 + box] = down(tn * cv) / np.maximum(down(cv), 1e-3)
    V[y0:y0 + box, x0:x0 + box] = down(cv)
    C[y0:y0 + box, x0:x0 + box] = down(np.array(clear, float) / 255)
    return (T, V), C


def flame_warp(L, t):
    """Sway and stretch the flame about its base; returns the warped L (full frame)."""
    out = L.copy()
    ys, xs = np.mgrid[FY0:FY1, FX0:FX1].astype(float)
    wgt = np.clip((FBASE - ys) / 70.0, 0, 1) ** 1.4                       # 0 at the base, 1 at the tip
    sway = 5.0 * (0.65 * np.sin(2 * np.pi * 1.15 * t + 3.0 * wgt) + 0.35 * np.sin(2 * np.pi * 2.9 * t + 1.7 + 5 * wgt))
    stretch = 1 + 0.08 * np.sin(2 * np.pi * 1.7 * t) + 0.04 * np.sin(2 * np.pi * 4.1 * t + 0.6)
    src_y = FBASE - (FBASE - ys) / stretch
    src_x = xs - sway * wgt
    region = ndimage.map_coordinates(L, [src_y, src_x], order=1, mode="nearest")
    out[FY0:FY1, FX0:FX1] = region
    return out


# twinkling four-point sparkles around the flame: (dx, dy, max radius, period s, phase)
TWINKLES = [(-26, -30, 9, 0.9, 0.00), (24, -38, 7, 1.1, 0.30), (34, -8, 8, 0.8, 0.55), (-34, 2, 6, 1.3, 0.70),
            (14, -52, 6, 0.7, 0.20), (-12, -50, 5, 1.0, 0.85), (30, -26, 5, 0.6, 0.40), (-24, -14, 5, 1.2, 0.10)]
# embers rising from the flame tip: (x offset, period s, phase, drift)
EMBERS = [(-4, 1.5, 0.00, 6), (3, 1.3, 0.25, -5), (0, 1.7, 0.50, 7), (6, 1.4, 0.75, -6), (-7, 1.6, 0.10, 4), (2, 1.2, 0.60, -4)]
SX0, SY0, SX1, SY1 = 900, 770, 1040, 905
SP_SS = 4


def add_sparkles(img, t, presence):
    if presence <= 0.05:
        return img
    w, h = (SX1 - SX0) * SP_SS, (SY1 - SY0) * SP_SS
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def P(x, y):
        return ((x - SX0) * SP_SS, (y - SY0) * SP_SS)

    def star(x, y, r, alpha):
        k = 0.2
        pts = [(0, -r), (k * r, -k * r), (r, 0), (k * r, k * r), (0, r), (-k * r, k * r), (-r, 0), (-k * r, -k * r)]
        d.polygon([P(x + px, y + py) for px, py in pts], fill=(255, 255, 255, int(alpha)))
        gx, gy = P(x, y)
        gr = r * 0.35 * SP_SS
        d.ellipse([gx - gr, gy - gr, gx + gr, gy + gr], fill=(255, 255, 255, int(alpha * 0.9)))

    for dx, dy, rmax, period, phase in TWINKLES:
        a = (0.5 + 0.5 * np.sin(2 * np.pi * (t / period + phase))) ** 2.2
        if a > 0.03:
            star(FCX + dx, FCY + dy, rmax * 1.4 * (0.4 + 0.6 * a), 255 * min(1.0, a * 1.5) * presence)
    for ox, period, phase, drift in EMBERS:
        q = ((t / period) + phase) % 1.0
        x = FCX + 8 + ox + drift * np.sin(2 * np.pi * q * 1.3)
        y = 846 - 58 * q
        alpha = 255 * min(1.0, q * 6) * (1 - q) ** 0.9 * presence
        r = 3.4 * (1 - 0.5 * q)
        cx_, cy_ = P(x, y)
        rr = r * SP_SS
        d.ellipse([cx_ - rr, cy_ - rr, cx_ + rr, cy_ + rr], fill=(246, 242, 255, int(alpha)))
    layer = layer.resize((SX1 - SX0, SY1 - SY0), Image.LANCZOS)
    base = img.convert("RGBA")
    base.alpha_composite(layer, (SX0, SY0))
    return base.convert("RGB")


def process(L_in, T, V, C, A, xx, t, presence):
    """L_in: luminance (0..1) of the source frame. A: how far the tabla has cross-faded in (0..1)."""
    L = L_in * (1 - C * A)
    a = V * A
    L = L * (1 - a) + T * a
    L = flame_warp(L, t)
    # soft pulsing glow around the flame, in luminance space (shows as violet haze on the navy)
    yy, xx2 = np.mgrid[FY0 - 40:FY1 + 40, FX0 - 40:FX1 + 40].astype(float)
    flick = 0.5 + 0.5 * np.sin(2 * np.pi * 1.7 * t) * 0.6 + 0.2 * np.sin(2 * np.pi * 4.1 * t + 0.6)
    glow = np.exp(-(((xx2 - FCX) / 26.0) ** 2 + ((yy - FCY) / 34.0) ** 2)) * (0.16 + 0.10 * flick) * presence
    sl = (slice(FY0 - 40, FY1 + 40), slice(FX0 - 40, FX1 + 40))
    L[sl] = np.clip(L[sl] + glow * (1 - L[sl]), 0, 1)
    L3 = L[..., None]
    low = BG + (NOTE - BG) * np.clip(L3 / 0.5, 0, 1)
    high = NOTE + (LOGO - NOTE) * np.clip((L3 - 0.5) / 0.5, 0, 1)
    out = np.where(L3 <= 0.5, low, high)
    # bright core inside the flame
    m = np.zeros_like(L)
    m[FY0:FY1, FX0:FX1] = (L[FY0:FY1, FX0:FX1] > 0.8)
    core = np.clip((ndimage.gaussian_filter(m, 4.0) - 0.62) / 0.3, 0, 1)
    rows = np.arange(core.shape[0])[:, None]
    core *= np.clip((FBASE - 8 - rows) / 28.0, 0, 1)             # core fades out toward the base, no hard edge
    out = out * (1 - core[..., None] * 0.9) + CORE * (core[..., None] * 0.9)
    return add_sparkles(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)), t, presence)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    preview = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == "--preview" else None
    tmp = tempfile.mkdtemp()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, f"{tmp}/f_%03d.png"], check=True)
    frames = sorted(glob.glob(f"{tmp}/f_*.png"))
    n = len(frames)
    first = Image.open(frames[0]); w, h = first.size
    (T, V), C = tabla_layers(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - CX, yy - CY)
    ring = (r > 58) & (r < 80)
    final_L = np.array(Image.open(frames[-1]).convert("L"), float)
    ring_final = final_L[ring].mean()
    flame_final = (final_L[FY0:FY1, FX0:FX1] > 128).sum()
    os.makedirs(f"{tmp}/out", exist_ok=True)
    total = n + EXTRA_FRAMES
    for i in range(1, total + 1):
        if preview and i != preview:
            continue
        im = Image.open(frames[min(i, n) - 1])
        L = np.array(im.convert("L"), float)
        cov = np.clip(L[ring].mean() / ring_final, 0, 1)
        A = float(np.clip((cov - 0.4) / 0.3, 0, 1))             # cross-fade ring -> tabla as the ring draws in
        presence = float(np.clip((L[FY0:FY1, FX0:FX1] > 128).sum() / flame_final, 0, 1))
        out = process(L / 255.0, T, V, C, A, xx, (i - 1) / FPS, presence)
        if preview:
            out.save(dst); return
        out.save(f"{tmp}/out/o_{i:03d}.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", f"{tmp}/out/o_%03d.png",
                    "-i", src, "-filter_complex", f"[1:a]apad=whole_dur={total / FPS}[a]",
                    "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-crf", "18", "-preset", "slow",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-t", f"{total / FPS}", dst], check=True)


if __name__ == "__main__":
    main()
