"""Builds Zikky's app icon (assets/Zikky.icns) and the welcome screen's logo
(assets/logo.png, the rounded square on transparency) from logo.png.

logo.png is the rounded square on an off-white page. macOS 26 puts a legacy
icon whose shape isn't its own rounded square on a grey tile, so the icon is
full-bleed: the square's art fills the canvas, its corners (rounder than
Apple's) filled with the navy of their row, and the system rounds it.

Usage: python3 design/icon.py  (needs Pillow and numpy)
"""
import os, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = Image.open(os.path.join(ROOT, "logo.png")).convert("RGB")

# Outside = light pixels connected to the border (the wings are light too, but
# enclosed by the dark square).
light = Image.fromarray(((np.asarray(src).mean(2) > 150) * 255).astype(np.uint8))
pad = Image.new("L", (light.width + 2, light.height + 2), 255)
pad.paste(light, (1, 1))
ImageDraw.floodfill(pad, (0, 0), 128)
inside = np.asarray(pad)[1:-1, 1:-1] != 128
# Trim the antialiased rim (it rings light/dark).
mask = Image.fromarray((inside * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(7))
box = mask.getbbox()
art = np.asarray(src.crop(box)).astype(float)
alpha = np.asarray(mask.crop(box).filter(ImageFilter.GaussianBlur(1.2))).astype(float)[..., None] / 255
core = np.asarray(mask.crop(box).filter(ImageFilter.MinFilter(9))) > 0

# Each row's navy: the mean of its innermost-edge pixels on both sides.
fill = np.zeros_like(art)
for y in range(art.shape[0]):
    xs = np.nonzero(core[y])[0]
    if len(xs):
        fill[y] = np.concatenate([art[y, xs[:24]], art[y, xs[-24:]]]).mean(0)
    else:
        fill[y] = fill[y - 1] if y else art[core].mean(0)
for y in range(art.shape[0] - 2, -1, -1):  # rows above the first inside row
    if not core[y].any():
        fill[y] = fill[y + 1]
fill = np.asarray(Image.fromarray(fill.astype(np.uint8)).filter(ImageFilter.GaussianBlur(8))).astype(float)

cutout = np.dstack([art, alpha[..., 0] * 255]).round().astype(np.uint8)
Image.fromarray(cutout).resize((256, 256), Image.LANCZOS).save(os.path.join(ROOT, "assets", "logo.png"))

full = art * alpha + fill * (1 - alpha)
canvas = Image.fromarray(full.round().astype(np.uint8)).resize((1024, 1024), Image.LANCZOS)

with tempfile.TemporaryDirectory() as tmp:
    iconset = os.path.join(tmp, "Zikky.iconset")
    os.mkdir(iconset)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            canvas.resize((pt * scale,) * 2, Image.LANCZOS).save(os.path.join(iconset, name))
    out = os.path.join(ROOT, "assets", "Zikky.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
canvas.save(os.path.join(ROOT, "design", "icon.png"))
print("wrote assets/Zikky.icns, assets/logo.png, design/icon.png", file=sys.stderr)
