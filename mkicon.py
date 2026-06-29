#!/usr/bin/env python3
"""Generate Android launcher icons from the official HolyC logo (CC0)."""
from PIL import Image, ImageDraw
import os

SRC = "/tmp/holyc_logo.png"
BASE = "/root/holyc-ide/app/src/main/res"
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
BG = (20, 23, 28, 255)

logo = Image.open(SRC).convert("RGBA")

def make_icon(size, round_=False):
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)

    # Dark rounded-square background
    r = int(size * 0.22)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=BG)

    # Fit logo with padding
    pad = int(size * 0.12)
    inner = size - pad * 2
    resized = logo.resize((inner, inner), Image.LANCZOS)
    icon.paste(resized, (pad, pad), resized)

    if round_:
        # Circular mask for ic_launcher_round
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.paste(icon, mask=mask)
        return out

    return icon

for density, size in SIZES.items():
    d = f"{BASE}/mipmap-{density}"
    os.makedirs(d, exist_ok=True)
    make_icon(size).save(f"{d}/ic_launcher.png")
    make_icon(size, round_=True).save(f"{d}/ic_launcher_round.png")
    print(f"  {density}: {size}x{size}")

print("Done.")
