#!/usr/bin/env python3
"""Prims Paste brand from the public Prim mark (mark-tight.png), not the favicon."""
from __future__ import annotations

import math
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "brand"
FONTS = BRAND / "fonts"
SOURCE = BRAND / "prim-mark-source.png"

# Prim brand tokens (prim-web/brand/prim/kit.css)
INK = (0x0C, 0x0C, 0x0E, 255)
PAPER = (0xF4, 0xF3, 0xEF, 255)
GOLD = (0xE8, 0xC5, 0x47, 255)
GOLD_CREASE = (0xC4, 0x9E, 0x2C, 255)

# Measured peak of mark-tight.png (the public Prim mark).
PEAK = (224.0, 9.0)
INNER = (60.0, 92.0)  # lightning vertex of the upper sheet
FOLD = 52.0


def along(origin, dest, dist: float):
    vx, vy = dest[0] - origin[0], dest[1] - origin[1]
    length = math.hypot(vx, vy)
    return (origin[0] + vx / length * dist, origin[1] + vy / length * dist)


def load_mask() -> Image.Image:
    im = Image.open(SOURCE).convert("RGBA")
    a = np.array(im)
    lum = a[:, :, :3].astype(np.int16).mean(axis=2)
    mask = ((a[:, :, 3] > 128) & (lum < 80)).astype(np.uint8) * 255
    return Image.fromarray(mask).convert("L")


def fold_points():
    a = (PEAK[0], PEAK[1] + FOLD)  # down the vertical right edge
    b = along(PEAK, INNER, FOLD)
    return PEAK, a, b


def potrace_svg(mask: Image.Image, dest: Path, fill: str) -> None:
    """Trace the black mark (potrace treats black as foreground)."""
    from PIL import ImageOps

    with tempfile.TemporaryDirectory() as tmp:
        pbm = Path(tmp) / "mark.pbm"
        ImageOps.invert(mask).convert("1").save(pbm)
        raw = Path(tmp) / "raw.svg"
        subprocess.check_call(["potrace", "-s", "-o", str(raw), str(pbm)])
        svg = raw.read_text()
        svg = svg.replace('fill="#000000"', f'fill="{fill}"')
        svg = svg.replace('fill="black"', f'fill="{fill}"')
        dest.write_text(svg)


def render_lockup(mark_ink: Image.Image, mark_paste: Image.Image) -> None:
    font = ImageFont.truetype(str(FONTS / "InstrumentSans-Variable.ttf"), 168)
    font.set_variation_by_axes([100, 650])
    text = "Prims Paste"

    target_h = 280
    ratio = target_h / mark_ink.size[1]
    ink_m = mark_ink.resize((round(mark_ink.size[0] * ratio), target_h), Image.Resampling.LANCZOS)
    paste_m = mark_paste.resize((round(mark_paste.size[0] * ratio), target_h), Image.Resampling.LANCZOS)

    dummy = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    bbox = dummy.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    gap, pad_x, pad_y = 56, 72, 64
    w = pad_x + ink_m.size[0] + gap + tw + pad_x
    h = pad_y + max(ink_m.size[1], th) + pad_y
    my = (h - ink_m.size[1]) // 2
    tx = pad_x + ink_m.size[0] + gap
    ty = (h - th) // 2 - bbox[1]

    paper = Image.new("RGBA", (w, h), PAPER)
    paper.alpha_composite(ink_m, (pad_x, my))
    ImageDraw.Draw(paper).text((tx, ty), text, font=font, fill=INK[:3])
    paper.save(BRAND / "lockup-paper.png")

    ink = Image.new("RGBA", (w, h), INK)
    ink.alpha_composite(paste_m, (pad_x, my))
    ImageDraw.Draw(ink).text((tx, ty), text, font=font, fill=PAPER[:3])
    ink.save(BRAND / "lockup-ink.png")
    print(f"png  brand/lockup-paper.png  {paper.size}")
    print(f"png  brand/lockup-ink.png    {ink.size}")


def render_icns(icon: Image.Image) -> None:
    tmp = Path(tempfile.mkdtemp(prefix="prims-paste-"))
    iconset = tmp / "AppIcon.iconset"
    iconset.mkdir()
    specs = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for size, name in specs:
        icon.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name)
    icns = BRAND / "AppIcon.icns"
    subprocess.check_call(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)])
    shutil.rmtree(tmp)
    print(f"icns {icns.relative_to(ROOT)}")


def rsvg(svg: Path, png: Path, height: int) -> None:
    subprocess.check_call(["rsvg-convert", "-h", str(height), str(svg), "-o", str(png)])


def write_icon_svg(mark_svg: Path) -> None:
    """Ink field, paper mark, gold dog-ear. Source mark is 233×378."""
    src_w, src_h = 233.0, 378.0
    canvas = 1024.0
    mark_h = 640.0
    s = mark_h / src_h
    dx = (canvas - src_w * s) / 2.0
    dy = (canvas - src_h * s) / 2.0
    peak, a, b = fold_points()
    mx, my = ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
    inward = (mx - peak[0], my - peak[1])
    under = (mx + inward[0] * 0.28, my + inward[1] * 0.28)

    import re

    raw = mark_svg.read_text()
    ds = re.findall(r"<path[^>]*d=\"([^\"]+)\"", raw)
    if len(ds) < 2:
        raise SystemExit(f"potrace expected 2 paths, got {len(ds)}")
    path_els = "\n".join(f'      <path d="{d}"/>' for d in ds)
    (BRAND / "icon.svg").write_text(
        f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#0c0c0e"/>
  <g transform="translate({dx:.4f} {dy:.4f}) scale({s:.6f})">
    <g transform="translate(0 378) scale(0.1 -0.1)" fill="#f4f3ef">
{path_els}
    </g>
    <polygon fill="#e8c547" points="{peak[0]:.2f},{peak[1]:.2f} {a[0]:.2f},{a[1]:.2f} {b[0]:.2f},{b[1]:.2f}"/>
    <polygon fill="#c49e2c" points="{a[0]:.2f},{a[1]:.2f} {b[0]:.2f},{b[1]:.2f} {under[0]:.2f},{under[1]:.2f}"/>
  </g>
</svg>
'''
    )


def main() -> None:
    BRAND.mkdir(exist_ok=True)
    mask = load_mask()

    potrace_svg(mask, BRAND / "mark-ink.svg", "#0c0c0e")
    write_icon_svg(BRAND / "mark-ink.svg")

    # High-res rasters from vectors (not from the 233px PNG).
    rsvg(BRAND / "mark-ink.svg", BRAND / "mark-ink.png", 1600)
    rsvg(BRAND / "icon.svg", BRAND / "icon.png", 1024)

    # Isolated paste mark: paper fill of the traced mark, then gold fold.
    paper_svg = BRAND / "mark-ink.svg"
    tmp_paper = BRAND / "mark-paper-tmp.svg"
    tmp_paper.write_text(paper_svg.read_text().replace('fill="#0c0c0e"', 'fill="#f4f3ef"'))
    rsvg(tmp_paper, BRAND / "mark-paper-tmp.png", 1600)
    paper_hi = Image.open(BRAND / "mark-paper-tmp.png").convert("RGBA")
    sx = paper_hi.size[0] / 233.0
    sy = paper_hi.size[1] / 378.0

    def mappt(p):
        return (p[0] * sx, p[1] * sy)

    peak, a, b = fold_points()
    overlay = Image.new("RGBA", paper_hi.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    d.polygon([mappt(peak), mappt(a), mappt(b)], fill=GOLD)
    mx, my = ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)
    inward = (mx - peak[0], my - peak[1])
    under = (mx + inward[0] * 0.28, my + inward[1] * 0.28)
    d.polygon([mappt(a), mappt(b), mappt(under)], fill=GOLD_CREASE)
    mark_paste = Image.alpha_composite(paper_hi, overlay)
    mark_paste.save(BRAND / "mark-paste.png")
    tmp_paper.unlink()
    (BRAND / "mark-paper-tmp.png").unlink()

    mark_ink = Image.open(BRAND / "mark-ink.png").convert("RGBA")
    icon = Image.open(BRAND / "icon.png").convert("RGBA")
    render_lockup(mark_ink, mark_paste)
    render_icns(icon)
    print("ok")


if __name__ == "__main__":
    main()
