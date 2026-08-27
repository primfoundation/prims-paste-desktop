#!/usr/bin/env python3
"""Pixel + OCR + bundle proofs for the Prims Paste mark. Exit 1 on fail."""
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


def load(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def near(px, rgb, tol=28):
    return all(abs(int(px[i]) - rgb[i]) <= tol for i in range(3))


def main() -> int:
    PROOF.mkdir(exist_ok=True)
    icon = load(BRAND / "icon.png")
    check("icon 1024", icon.size == (1024, 1024), str(icon.size))

    a = np.array(icon)
    ink = (a[:, :, 0] < 30) & (a[:, :, 1] < 30) & (a[:, :, 2] < 36)
    paper = (a[:, :, 0] > 220) & (a[:, :, 1] > 218) & (a[:, :, 2] > 210)
    gold = (a[:, :, 0] > 180) & (a[:, :, 1] > 140) & (a[:, :, 2] < 120) & (a[:, :, 1] > a[:, :, 2] + 20)
    check("ink field", int(ink.mean() * 100) >= 55, f"{ink.mean():.2%}")
    check("paper sheets", int(paper.sum()) >= 8000, str(int(paper.sum())))
    check("gold fold", int(gold.sum()) >= 80, str(int(gold.sum())))

    # Gold lives in the upper-right quadrant of the mark, not the lower sheet.
    ys, xs = np.where(gold)
    if len(xs):
        check("gold is high", float(ys.mean()) < 512, f"mean y {ys.mean():.0f}")
        check("gold is right", float(xs.mean()) > 512, f"mean x {xs.mean():.0f}")
    else:
        check("gold is high", False)
        check("gold is right", False)

    left = int(paper[380:900, 280:520].sum())
    right = int(paper[180:720, 520:820].sum())
    check("left sheet", left >= 1500, str(left))
    check("right sheet", right >= 1500, str(right))
    gap = int(paper[430:620, 470:620].sum())
    check("lightning gap is dark", gap < left * 0.25, str(gap))

    mark = load(BRAND / "mark-paste.png")
    ma = np.array(mark)
    check("paste mark has alpha", int((ma[:, :, 3] < 10).sum()) > 1000)
    check(
        "paste mark gold",
        int(((ma[:, :, 0] > 180) & (ma[:, :, 1] > 140) & (ma[:, :, 2] < 120) & (ma[:, :, 3] > 200)).sum())
        >= 80,
    )

    # 16px Dock size still has paper + gold.
    tiny = icon.resize((16, 16), Image.Resampling.LANCZOS)
    t = np.array(tiny)
    check(
        "16px still paper",
        int(((t[:, :, 0] > 200) & (t[:, :, 1] > 200) & (t[:, :, 2] > 190)).sum()) >= 2,
    )
    check(
        "16px still gold-ish",
        int(((t[:, :, 0] > 150) & (t[:, :, 1] > 110) & (t[:, :, 2] < 140)).sum()) >= 1,
    )
    tiny.save(PROOF / "icon-16.png")
    icon.resize((32, 32), Image.Resampling.LANCZOS).save(PROOF / "icon-32.png")
    icon.resize((128, 128), Image.Resampling.LANCZOS).save(PROOF / "icon-128.png")

    # Installed app matches repo icns.
    app_icns = APP / "Contents/Resources/AppIcon.icns"
    repo_icns = BRAND / "AppIcon.icns"
    check("installed icns exists", app_icns.is_file())
    if app_icns.is_file() and repo_icns.is_file():
        check(
            "installed icns matches repo",
            hashlib.sha256(app_icns.read_bytes()).digest()
            == hashlib.sha256(repo_icns.read_bytes()).digest(),
        )
    paste = APP / "Contents/Resources/PasteMark.png"
    check("installed PasteMark exists", paste.is_file())
    if paste.is_file() and (BRAND / "mark-paste.png").is_file():
        check(
            "installed PasteMark matches repo",
            hashlib.sha256(paste.read_bytes()).digest()
            == hashlib.sha256((BRAND / "mark-paste.png").read_bytes()).digest(),
        )

    # OCR lockup.
    lockup = BRAND / "lockup-paper.png"
    ocr_txt = ocr(lockup)
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
