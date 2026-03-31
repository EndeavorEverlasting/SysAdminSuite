#!/usr/bin/env python3
"""
Shared parsing helpers for workstation/printer map PDFs and images.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import cv2
import numpy as np

try:
    import pytesseract
except Exception:  # pragma: no cover - optional dependency
    pytesseract = None


ColorRange = Tuple[np.ndarray, np.ndarray]
Point = Tuple[int, int, int]
EntityRow = Tuple[int, int, int]


RED_RANGES: Sequence[ColorRange] = (
    (np.array([0, 100, 100]), np.array([10, 255, 255])),
    (np.array([160, 100, 100]), np.array([179, 255, 255])),
)
GREEN_RANGES: Sequence[ColorRange] = (
    (np.array([35, 40, 40]), np.array([85, 255, 255])),
)


def parse_args_common(description: str) -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=description)
    ap.add_argument("--map", required=True, help="Map file path (PDF or image)")
    ap.add_argument("--out-csv", required=True, help="Output CSV path")
    ap.add_argument("--out-overlay", default="", help="Optional overlay PNG output path")
    ap.add_argument("--expected-min", type=int, default=1)
    ap.add_argument("--expected-max", type=int, default=999)
    ap.add_argument("--dpi", type=int, default=300, help="PDF render DPI")
    ap.add_argument("--min-radius", type=int, default=9)
    ap.add_argument("--max-radius", type=int, default=60)
    return ap


def load_map_bgr(path: str, dpi: int = 300) -> np.ndarray:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Input map not found: {path}")
    if p.suffix.lower() != ".pdf":
        img = cv2.imread(str(p))
        if img is None:
            raise ValueError(f"Cannot read map image: {path}")
        return img

    try:
        import pypdfium2 as pdfium  # type: ignore
    except Exception as exc:
        raise RuntimeError(
            "PDF input requires pypdfium2. Install with: pip install pypdfium2"
        ) from exc

    doc = pdfium.PdfDocument(str(p))
    if len(doc) < 1:
        raise ValueError(f"PDF has no pages: {path}")
    scale = max(dpi, 72) / 72.0
    bmp = doc[0].render(scale=scale).to_numpy()
    if bmp is None or bmp.size == 0:
        raise ValueError(f"Failed to render PDF page: {path}")
    if len(bmp.shape) == 2:
        return cv2.cvtColor(bmp, cv2.COLOR_GRAY2BGR)
    if bmp.shape[2] == 4:
        return cv2.cvtColor(bmp, cv2.COLOR_BGRA2BGR)
    return bmp


def mask_color(hsv: np.ndarray, ranges: Sequence[ColorRange]) -> np.ndarray:
    mask = None
    for lo, hi in ranges:
        m = cv2.inRange(hsv, lo, hi)
        m = cv2.medianBlur(m, 5)
        mask = m if mask is None else cv2.bitwise_or(mask, m)
    kernel = np.ones((3, 3), np.uint8)
    return cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)


def detect_marker_points(
    bgr: np.ndarray,
    ranges: Sequence[ColorRange],
    min_radius: int = 9,
    max_radius: int = 60,
) -> List[Point]:
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    mask = mask_color(hsv, ranges)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    points: List[Point] = []
    for cnt in contours:
        (x, y), radius = cv2.minEnclosingCircle(cnt)
        if radius < min_radius or radius > max_radius:
            continue
        points.append((int(x), int(y), int(radius)))
    return points


def ocr_digits(roi_bgr: np.ndarray) -> str:
    if pytesseract is None:
        raise RuntimeError(
            "OCR requires pytesseract. Install with: pip install pytesseract"
        )
    gray = cv2.cvtColor(roi_bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (3, 3), 0)
    thr = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C, cv2.THRESH_BINARY_INV, 31, 10
    )
    up = cv2.resize(thr, None, fx=6, fy=6, interpolation=cv2.INTER_CUBIC)
    text = pytesseract.image_to_string(
        up, config="--psm 7 -c tessedit_char_whitelist=0123456789"
    )
    return re.sub(r"[^\d]", "", text)


def extract_entities(
    bgr: np.ndarray,
    ranges: Sequence[ColorRange],
    expected_min: int,
    expected_max: int,
    min_radius: int = 9,
    max_radius: int = 60,
) -> List[EntityRow]:
    rows: List[EntityRow] = []
    raw = detect_marker_points(bgr, ranges, min_radius=min_radius, max_radius=max_radius)
    for x, y, r in raw:
        pad = int(r * 1.7)
        x1, y1 = max(0, x - pad), max(0, y - pad)
        x2, y2 = min(bgr.shape[1], x + pad), min(bgr.shape[0], y + pad)
        roi = bgr[y1:y2, x1:x2]
        txt = ocr_digits(roi)
        if not txt:
            continue
        try:
            num = int(txt)
        except ValueError:
            continue
        if num < expected_min and num < 100 and expected_min >= 100:
            num = 100 + num
        if num > expected_max:
            digits = str(num)
            keep = 3 if expected_max >= 100 else 2
            num = int(digits[-keep:]) if len(digits) >= keep else int(digits)
        rows.append((num, x, y))
    rows.sort(key=lambda t: (t[0], t[1], t[2]))
    return rows


def write_entities_csv(rows: Sequence[EntityRow], output_csv: str, id_column: str) -> None:
    with open(output_csv, "w", encoding="utf-8", newline="") as fh:
        fh.write(f"{id_column},x,y\n")
        for rid, x, y in sorted(rows, key=lambda t: t[0]):
            fh.write(f"{rid},{x},{y}\n")


def draw_overlay(bgr: np.ndarray, rows: Sequence[EntityRow], bgr_color: Tuple[int, int, int], label: str) -> np.ndarray:
    out = bgr.copy()
    for rid, x, y in rows:
        cv2.circle(out, (x, y), 16, bgr_color, 2)
        cv2.putText(
            out, str(rid), (x - 14, y - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.6, bgr_color, 2, cv2.LINE_AA
        )
    cv2.putText(out, label, (15, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, bgr_color, 2, cv2.LINE_AA)
    return out


def summarize_quality(rows: Sequence[EntityRow]) -> Dict[str, int]:
    return {"count": len(rows), "distinct_ids": len({r[0] for r in rows})}
