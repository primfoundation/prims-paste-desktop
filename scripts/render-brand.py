#!/usr/bin/env python3
"""Render Prims Paste brand from the official Prim folio (prim.brand)."""
from __future__ import annotations

import hashlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "brand"
FONTS = BRAND / "fonts"

INK = "#0c0c0e"
PAPER = "#f4f3ef"
GOLD = "#e8c547"


def write_icon_svg() -> None:
    # Gold folio on ink. Clear space > 1× spine (16/200 of the mark).
    (BRAND / "icon.svg").write_text(
        f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="{INK}"/>
  <g transform="translate(212 212) scale(3)" fill="{GOLD}">
    <rect x="56" y="30" width="16" height="140"/>
    <path d="M72 30h50l24 24v116H72Z"/>
  </g>
</svg>
'''
    )


def write_mark_svg(path: Path, fill: str) -> None:
    path.write_text(
        f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
  <rect x="56" y="30" width="16" height="140" fill="{fill}"/>
  <path d="M72 30h50l24 24v116H72Z" fill="{fill}"/>
</svg>
'''
    )


def rsvg(svg: Path, png: Path, width: int) -> None:
    subprocess.check_call(["rsvg-convert", "-w", str(width), str(svg), "-o", str(png)])


def render_lockup() -> None:
    font = ImageFont.truetype(str(FONTS / "InstrumentSans-Variable.ttf"), 168)
    font.set_variation_by_axes([100, 650])
    mark = Image.open(BRAND / "mark-ink.png").convert("RGBA")
    target_h = 280
    ratio = target_h / mark.size[1]
    mark = mark.resize((round(mark.size[0] * ratio), target_h), Image.Resampling.LANCZOS)
    text = "Prims Paste"
    dummy = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    bbox = dummy.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    gap, pad_x, pad_y = 48, 72, 64
    w = pad_x + mark.size[0] + gap + tw + pad_x
    h = pad_y + max(mark.size[1], th) + pad_y
    my = (h - mark.size[1]) // 2
    tx = pad_x + mark.size[0] + gap
    ty = (h - th) // 2 - bbox[1]

    paper = Image.new("RGBA", (w, h), (0xF4, 0xF3, 0xEF, 255))
    paper.alpha_composite(mark, (pad_x, my))
    ImageDraw.Draw(paper).text((tx, ty), text, font=font, fill=(0x0C, 0x0C, 0x0E))
    paper.save(BRAND / "lockup-paper.png")

    gold = Image.open(BRAND / "mark-gold.png").convert("RGBA")
    gold = gold.resize((round(gold.size[0] * ratio), target_h), Image.Resampling.LANCZOS)
    ink = Image.new("RGBA", (w, h), (0x0C, 0x0C, 0x0E, 255))
    ink.alpha_composite(gold, (pad_x, my))
    ImageDraw.Draw(ink).text((tx, ty), text, font=font, fill=(0xF4, 0xF3, 0xEF))
    ink.save(BRAND / "lockup-ink.png")
    print(f"lockup {paper.size}")


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


def main() -> None:
    BRAND.mkdir(exist_ok=True)
    write_icon_svg()
    write_mark_svg(BRAND / "mark-ink.svg", INK)
    write_mark_svg(BRAND / "mark-gold.svg", GOLD)
    write_mark_svg(BRAND / "mark-cream.svg", PAPER)
    rsvg(BRAND / "icon.svg", BRAND / "icon.png", 1024)
    rsvg(BRAND / "mark-ink.svg", BRAND / "mark-ink.png", 800)
    rsvg(BRAND / "mark-gold.svg", BRAND / "mark-gold.png", 800)
    rsvg(BRAND / "mark-cream.svg", BRAND / "mark-cream.png", 800)
    # Unlock / in-app: ink folio on a clear field (paper chrome).
    Image.open(BRAND / "mark-ink.png").convert("RGBA").save(BRAND / "mark-paste.png")
    render_lockup()
    render_icns(Image.open(BRAND / "icon.png").convert("RGBA"))
    print("sha icon", hashlib.sha256((BRAND / "icon.png").read_bytes()).hexdigest()[:12])
    print("ok")


if __name__ == "__main__":
    main()
