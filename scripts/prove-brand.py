#!/usr/bin/env python3
"""Pixel + OCR + bundle proofs for the Prim folio on Prims Paste."""
from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "brand"
APP = Path.home() / "Applications" / "Prims Paste.app"
PROOF = Path("/tmp/prims-paste-brand-proof")
failed = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global failed
    print(f"{'PASS' if ok else 'FAIL'} — {name}" + (f" ({detail})" if detail else ""))
    if not ok:
        failed += 1


def main() -> int:
    PROOF.mkdir(exist_ok=True)
    icon = Image.open(BRAND / "icon.png").convert("RGBA")
    check("icon 1024", icon.size == (1024, 1024), str(icon.size))
    a = np.array(icon)
    ink = (a[:, :, 0] < 30) & (a[:, :, 1] < 30) & (a[:, :, 2] < 36)
    gold = (a[:, :, 0] > 180) & (a[:, :, 1] > 140) & (a[:, :, 2] < 120) & (a[:, :, 1] > a[:, :, 2] + 20)
    cream = (a[:, :, 0] > 220) & (a[:, :, 1] > 218) & (a[:, :, 2] > 210)
    check("ink field", ink.mean() >= 0.55, f"{ink.mean():.2%}")
    check("gold folio", int(gold.sum()) >= 4000, str(int(gold.sum())))
    check("not cream sheets", int(cream.sum()) < int(gold.sum()) // 4, str(int(cream.sum())))
    ys, xs = np.where(gold)
    check("folio centered x", 400 < float(xs.mean()) < 624, f"{xs.mean():.0f}")
    check("folio centered y", 400 < float(ys.mean()) < 624, f"{ys.mean():.0f}")

    tiny = icon.resize((16, 16), Image.Resampling.LANCZOS)
    t = np.array(tiny)
    check(
        "16px still gold",
        int(((t[:, :, 0] > 140) & (t[:, :, 1] > 100) & (t[:, :, 2] < 140)).sum()) >= 1,
    )
    tiny.save(PROOF / "icon-16.png")
    icon.resize((32, 32), Image.Resampling.LANCZOS).save(PROOF / "icon-32.png")
    icon.resize((128, 128), Image.Resampling.LANCZOS).save(PROOF / "icon-128.png")

    app_icns = APP / "Contents/Resources/AppIcon.icns"
    check("installed icns exists", app_icns.is_file())
    if app_icns.is_file():
        check(
            "installed icns matches repo",
            hashlib.sha256(app_icns.read_bytes()).digest()
            == hashlib.sha256((BRAND / "AppIcon.icns").read_bytes()).digest(),
        )
    fonts = APP / "Contents/Resources/Fonts"
    check("Instrument Sans in app", (fonts / "InstrumentSans-Variable.ttf").is_file())
    check("IBM Plex Mono in app", (fonts / "IBMPlexMono-Regular.ttf").is_file())

    svg = (BRAND / "icon.svg").read_text()
    check("icon svg gold token", "#e8c547" in svg)
    check("icon svg ink token", "#0c0c0e" in svg)
    check("icon svg folio path", "M72 30h50l24 24v116H72Z" in svg)

    ocr_txt = ocr(BRAND / "lockup-paper.png")
    compact = "".join(ch.lower() for ch in ocr_txt if ch.isalnum() or ch.isspace())
    check("lockup OCR Prims", "prims" in compact, repr(ocr_txt.strip()[:80]))
    check("lockup OCR Paste", "paste" in compact, repr(ocr_txt.strip()[:80]))
    print(f"proof dir {PROOF}")
    return 1 if failed else 0


def ocr(path: Path) -> str:
    tes = subprocess.run(["which", "tesseract"], capture_output=True, text=True)
    if tes.returncode == 0:
        out = subprocess.run(
            ["tesseract", str(path), "stdout", "--psm", "7"],
            capture_output=True,
            text=True,
        )
        return out.stdout
    swift = r"""
import Vision
import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let img = NSImage(contentsOf: url)!
var imageRect = CGRect(origin: .zero, size: img.size)
let cg = img.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)!
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try! handler.perform([req])
let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
print(text)
"""
    with tempfile.NamedTemporaryFile("w", suffix=".swift", delete=False) as f:
        f.write(swift)
        src = f.name
    out = subprocess.run(["swift", src, str(path)], capture_output=True, text=True)
    return out.stdout + out.stderr


if __name__ == "__main__":
    sys.exit(main())
