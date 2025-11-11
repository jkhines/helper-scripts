#!/usr/bin/env python3
"""Create a single PNG mosaic for every PPTX in a directory.

Why not use LibreOffice's *png* exporter directly?  On Windows builds ≥7.4 a
known bug lets `--convert-to png` export only the first slide.  The workaround
here is:

1.  Use LibreOffice headless to convert the deck to PDF (all slides preserved).
2.  Rasterise each PDF page with *poppler* via **pdf2image**.
3.  Resize to the requested thumbnail size.
4.  Assemble the thumbnails into a grid using Pillow.

Dependencies (Windows / macOS / Linux):
    pip install pillow pdf2image
    # and make sure poppler is available:
    #   Windows: choco install poppler   (or get the ZIP from poppler.win)
    #   macOS : brew install poppler

LibreOffice must also be installed and its `soffice` executable either added
to PATH or left in the default install location.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import shutil
import tempfile
from math import ceil, sqrt
from pathlib import Path
import glob
import os

try:
    from pdf2image import convert_from_path  # type: ignore
    from PIL import Image  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.exit(f"Missing Python dependency: {exc.name}.  Run 'pip install pillow pdf2image'.")

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
DEF_WIDTH = 1280   # width of each thumbnail
DEF_HEIGHT = 720   # height of each thumbnail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def find_soffice() -> str:
    """Return a path to LibreOffice's `soffice` executable.

    Checks common install paths on Windows and falls back to whatever is in
    the current PATH.  Raises FileNotFoundError if not found.
    """
    candidates = [
        "soffice",  # already in PATH
        r"C:\\Program Files\\LibreOffice\\program\\soffice.exe",
        r"C:\\Program Files (x86)\\LibreOffice\\program\\soffice.exe",
        "/usr/bin/soffice",
        "/usr/local/bin/soffice",
    ]
    for path in candidates:
        # shutil.which() returns full path if found in PATH
        found = shutil.which(path)
        if found:
            return found
        if Path(path).is_file():
            return path
    raise FileNotFoundError("LibreOffice 'soffice' executable not found. Install LibreOffice or add it to PATH.")


def find_poppler_path() -> str:
    """Locate pdftoppm/pdftocairo binaries.

    Search order:
      1. Environment variable POPPLER_PATH
      2. Executable on PATH
      3. Chocolatey default install dir
    """
    env = os.getenv("POPPLER_PATH")
    if env and Path(env).is_dir():
        return env

    exe = shutil.which("pdftoppm") or shutil.which("pdftoppm.exe")
    if exe:
        return str(Path(exe).parent)

    choc_root = Path(r"C:\Tools\poppler")
    if choc_root.exists():
        exe_paths = sorted(choc_root.glob("**/pdftoppm.exe"), reverse=True)
        if exe_paths:
            return str(exe_paths[0].parent)

    raise FileNotFoundError("pdftoppm not found. Install Poppler and/or set POPPLER_PATH.")


def libreoffice_to_pdf(pptx: Path, out_dir: Path) -> Path:
    """Convert *pptx* to PDF using LibreOffice and return PDF path."""
    pdf_path = out_dir / (pptx.stem + ".pdf")
    cmd = [
        find_soffice(),
        "--headless",
        "--convert-to", "pdf",
        "--outdir", str(out_dir),
        str(pptx),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            "LibreOffice conversion failed (returncode %d).\nSTDOUT:\n%s\nSTDERR:\n%s"
            % (proc.returncode, proc.stdout, proc.stderr)
        )
    if not pdf_path.is_file():
        raise RuntimeError("LibreOffice reported success but PDF file not found.")
    return pdf_path


def pdf_pages_to_png(pdf: Path, tmp_dir: Path, width: int, height: int) -> list[Path]:
    """Rasterise each page of *pdf* into a resized PNG thumbnail."""
    # High DPI render → downscale gives better quality than direct low-rez render
    poppler_dir = find_poppler_path()
    pages = convert_from_path(pdf, dpi=300, poppler_path=poppler_dir)
    out_paths: list[Path] = []
    for idx, page in enumerate(pages, 1):
        page = page.resize((width, height), Image.LANCZOS)
        out_path = tmp_dir / f"slide_{idx:03}.png"
        page.save(out_path)
        out_paths.append(out_path)
    return out_paths


def build_mosaic(thumbnails: list[Path], out_file: Path, width: int, height: int) -> None:
    """Assemble *thumbnails* into a grid and save to *out_file*."""
    if not thumbnails:
        raise ValueError("No thumbnails to stitch.")

    cols = int(ceil(sqrt(len(thumbnails))))
    rows = int(ceil(len(thumbnails) / cols))

    canvas = Image.new("RGB", (cols * width, rows * height), "white")
    for idx, thumb_path in enumerate(thumbnails):
        with Image.open(thumb_path) as img:
            row, col = divmod(idx, cols)
            canvas.paste(img, (col * width, row * height))
    canvas.save(out_file, "PNG")


# ---------------------------------------------------------------------------
# Main processing
# ---------------------------------------------------------------------------

def process_deck(pptx: Path, width: int, height: int) -> None:
    print(f"Processing: {pptx.name}")
    with tempfile.TemporaryDirectory(prefix="pptx_mosaic_") as tmp_str:
        tmp = Path(tmp_str)
        try:
            pdf = libreoffice_to_pdf(pptx, tmp)
            thumbs = pdf_pages_to_png(pdf, tmp, width, height)
            output = pptx.with_suffix(".png")
            build_mosaic(thumbs, output, width, height)
            print(f"  ➜ {output.name}  ({len(thumbs)} slides)")
        except Exception as exc:
            print(f"FAILED  {pptx.name} – {exc}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a slide-deck mosaic PNG for PPTX files.")
    parser.add_argument("pptx_file", nargs="?", default=None, help="Path to a PPTX file to convert")
    parser.add_argument("--all", action="store_true", help="Process all PPTX files in the current directory")
    parser.add_argument("--width",  type=int, default=DEF_WIDTH,  help="Thumbnail width, px (default: 1280)")
    parser.add_argument("--height", type=int, default=DEF_HEIGHT, help="Thumbnail height, px (default: 720)")
    args = parser.parse_args()

    if args.pptx_file and args.all:
        print("Cannot specify both a file and --all.")
        parser.print_help()
        return

    if args.pptx_file:
        pptx_path = Path(args.pptx_file).expanduser().resolve()
        if not pptx_path.is_file() or pptx_path.suffix.lower() != ".pptx":
            print(f"Specified file '{pptx_path}' is not a valid PPTX file.")
            return
        decks = [pptx_path]
    elif args.all:
        root = Path(".").expanduser().resolve()
        decks = sorted(root.glob("*.pptx"))
        if not decks:
            print("No PPTX files found.")
            return
    else:
        parser.print_help()
        return

    for deck in decks:
        process_deck(deck, args.width, args.height)

    print("Done.")


if __name__ == "__main__":
    main() 