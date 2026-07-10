#!/usr/bin/env python3
"""Generates Resources/AppIcon.icns for CalmMeter.

Design: a macOS-style rounded "squircle" with a warm Claude-coral gradient,
a circular usage gauge (donut with a partial fill + rounded knob), and a small
Claude-style sunburst at the centre. Renders at 1024px, then sips/iconutil
produce the .icns.
"""
import math
import os
import subprocess
import tempfile
from PIL import Image, ImageDraw, ImageFilter

S = 1024  # master render size
SS = 4    # supersample factor for crisp edges
N = S * SS

# --- palette ----------------------------------------------------------------
CORAL_TOP = (233, 132, 100)     # #E98464  warm coral
CORAL_BOT = (193, 95, 60)       # #C15F3C  deeper terracotta
CREAM = (255, 249, 242)         # gauge fill / sunburst
TRACK = (255, 255, 255, 85)     # unfilled gauge track


def superellipse_mask(size, margin, n=5.0):
    """Apple-ish squircle alpha mask."""
    mask = Image.new("L", (size, size), 0)
    px = mask.load()
    a = (size - 2 * margin) / 2.0
    cx = cy = size / 2.0
    for y in range(size):
        dy = abs((y - cy) / a)
        if dy > 1.0:
            continue
        # solve |dx|^n <= 1 - dy^n  ->  dx <= (1 - dy^n)^(1/n)
        dxmax = (1.0 - dy ** n) ** (1.0 / n)
        xspan = dxmax * a
        x0 = int(cx - xspan)
        x1 = int(cx + xspan)
        for x in range(max(0, x0), min(size, x1 + 1)):
            px[x, y] = 255
    return mask


def vertical_gradient(size, top, bot):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return grad.resize((size, size))


def rounded_arc(draw, bbox, start, end, width, fill):
    """Arc with rounded caps."""
    draw.arc(bbox, start, end, fill=fill, width=width)
    cx = (bbox[0] + bbox[2]) / 2
    cy = (bbox[1] + bbox[3]) / 2
    r = (bbox[2] - bbox[0]) / 2
    for ang in (start, end):
        ex = cx + r * math.cos(math.radians(ang))
        ey = cy + r * math.sin(math.radians(ang))
        draw.ellipse([ex - width / 2, ey - width / 2, ex + width / 2, ey + width / 2], fill=fill)


def sunburst(draw, cx, cy, r_out, r_in, points, fill):
    """A rounded Claude-style asterisk/sunburst."""
    w = int(r_out * 0.22)
    for k in range(points):
        ang = math.radians(360.0 / points * k - 90)
        x0 = cx + r_in * math.cos(ang)
        y0 = cy + r_in * math.sin(ang)
        x1 = cx + r_out * math.cos(ang)
        y1 = cy + r_out * math.sin(ang)
        draw.line([x0, y0, x1, y1], fill=fill, width=w)
        # round caps
        for (px, py) in ((x1, y1),):
            draw.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=fill)
    draw.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in], fill=fill)


def render():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # background squircle with gradient
    margin = int(N * 0.085)
    mask = superellipse_mask(N, margin, n=5.0)
    grad = vertical_gradient(N, CORAL_TOP, CORAL_BOT).convert("RGBA")
    img.paste(grad, (0, 0), mask)

    # soft top highlight for depth
    hi = Image.new("L", (N, N), 0)
    ImageDraw.Draw(hi).ellipse([margin, int(margin - N * 0.15),
                                N - margin, int(N * 0.5)], fill=40)
    hi = hi.filter(ImageFilter.GaussianBlur(N * 0.03))
    white = Image.new("RGBA", (N, N), (255, 255, 255, 255))
    hi_masked = Image.composite(white, Image.new("RGBA", (N, N), (0, 0, 0, 0)), hi)
    img = Image.alpha_composite(img, Image.composite(hi_masked, Image.new("RGBA", (N, N), (0, 0, 0, 0)), mask))

    draw = ImageDraw.Draw(img)

    # gauge geometry
    cx = cy = N / 2
    gr = int(N * 0.30)          # gauge radius
    gw = int(N * 0.075)         # gauge stroke width
    bbox = [cx - gr, cy - gr, cx + gr, cy + gr]

    # track (full ring, no caps — avoids a stray nub)
    draw.arc(bbox, 0, 360, fill=TRACK, width=gw)
    # filled arc: start at top (-90) sweep ~68%
    start = -90
    sweep = 360 * 0.68
    rounded_arc(draw, bbox, start, start + sweep, gw, CREAM + (255,))

    # centre sunburst
    sunburst(draw, cx, cy, r_out=int(N * 0.135), r_in=int(N * 0.052),
             points=8, fill=CREAM + (255,))

    return img.resize((S, S), Image.LANCZOS)


def build_icns(png1024_path, out_icns):
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        specs = [
            (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
        ]
        for size, name in specs:
            subprocess.run(["sips", "-z", str(size), str(size), png1024_path,
                            "--out", os.path.join(iconset, name)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out_icns], check=True)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res = os.path.join(root, "Resources")
    os.makedirs(res, exist_ok=True)
    png = os.path.join(res, "AppIcon.png")
    icns = os.path.join(res, "AppIcon.icns")
    render().save(png)
    build_icns(png, icns)
    print("wrote", png)
    print("wrote", icns)


if __name__ == "__main__":
    main()
