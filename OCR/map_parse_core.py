#!/usr/bin/env python3
"""
Shared parsing helpers for workstation/printer map PDFs and images.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

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
    ap.add_argument("--out-html", default="", help="Optional HTML report output path")
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
    if mask is None:
        mask = np.zeros(hsv.shape[:2], dtype=np.uint8)
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


def ocr_digits_with_confidence(roi_bgr: np.ndarray) -> Tuple[str, float]:
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
    cfg = "--psm 7 -c tessedit_char_whitelist=0123456789"
    data = pytesseract.image_to_data(
        up, config=cfg, output_type=pytesseract.Output.DICT
    )
    tokens: List[str] = []
    confs: List[float] = []
    for text, conf in zip(data.get("text", []), data.get("conf", [])):
        digits = re.sub(r"[^\d]", "", str(text))
        if not digits:
            continue
        tokens.append(digits)
        try:
            conf_value = float(conf)
        except Exception:
            conf_value = -1.0
        if conf_value >= 0:
            confs.append(conf_value / 100.0)
    joined = "".join(tokens)
    if not joined:
        return "", 0.0
    if confs:
        return joined, float(max(0.0, min(1.0, sum(confs) / len(confs))))
    return joined, 0.5


def extract_entities_detailed(
    bgr: np.ndarray,
    ranges: Sequence[ColorRange],
    expected_min: int,
    expected_max: int,
    min_radius: int = 9,
    max_radius: int = 60,
    confidence_threshold: float = 0.75,
) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    raw = detect_marker_points(bgr, ranges, min_radius=min_radius, max_radius=max_radius)
    radius_span = max(1, max_radius - min_radius)
    for x, y, r in raw:
        pad = int(r * 1.7)
        x1, y1 = max(0, x - pad), max(0, y - pad)
        x2, y2 = min(bgr.shape[1], x + pad), min(bgr.shape[0], y + pad)
        roi = bgr[y1:y2, x1:x2]
        txt, text_conf = ocr_digits_with_confidence(roi)
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

        shape_conf = float(max(0.0, min(1.0, (r - min_radius) / radius_span)))
        confidence = float(max(0.0, min(1.0, (text_conf * 0.7) + (shape_conf * 0.3))))
        status = "certain" if confidence >= confidence_threshold else "ambiguous"
        rows.append(
            {
                "id": num,
                "x": x,
                "y": y,
                "radius": r,
                "text_confidence": round(text_conf, 4),
                "shape_confidence": round(shape_conf, 4),
                "confidence": round(confidence, 4),
                "status": status,
            }
        )
    rows.sort(key=lambda t: (int(t["id"]), int(t["x"]), int(t["y"])))
    return rows


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


def write_entities_detailed_csv(rows: Sequence[Dict[str, Any]], output_csv: str, id_column: str) -> None:
    with open(output_csv, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[id_column, "x", "y", "radius", "text_confidence", "shape_confidence", "confidence", "status"],
        )
        writer.writeheader()
        for row in sorted(rows, key=lambda t: int(t["id"])):
            writer.writerow(
                {
                    id_column: int(row["id"]),
                    "x": int(row["x"]),
                    "y": int(row["y"]),
                    "radius": int(row["radius"]),
                    "text_confidence": float(row["text_confidence"]),
                    "shape_confidence": float(row["shape_confidence"]),
                    "confidence": float(row["confidence"]),
                    "status": str(row["status"]),
                }
            )


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


def summarize_detailed_quality(rows: Sequence[Dict[str, Any]]) -> Dict[str, int]:
    return {
        "count": len(rows),
        "distinct_ids": len({int(r["id"]) for r in rows}),
        "certain_count": sum(1 for r in rows if str(r.get("status")) == "certain"),
        "ambiguous_count": sum(1 for r in rows if str(r.get("status")) == "ambiguous"),
    }


def detect_legend_rows(
    bgr: np.ndarray, right_ratio: float = 0.33
) -> List[Dict[str, Any]]:
    if pytesseract is None:
        return []
    h, w = bgr.shape[:2]
    right_ratio = max(0.1, min(0.8, right_ratio))
    x0 = int(w * (1.0 - right_ratio))
    roi = bgr[:, x0:w]
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    text = pytesseract.image_to_string(gray, config="--psm 6")
    rows: List[Dict[str, Any]] = []
    for line in text.splitlines():
        cleaned = re.sub(r"\s+", " ", line).strip()
        m = re.match(r"^(?P<count>\d+)\s+(?P<description>[A-Za-z][A-Za-z0-9\-/_, ()]+)$", cleaned)
        if not m:
            continue
        rows.append(
            {
                "count": int(m.group("count")),
                "description": m.group("description"),
                "raw": cleaned,
            }
        )
    return rows


def compare_detected_to_legend(
    detected_rows: Sequence[Dict[str, Any]],
    legend_rows: Sequence[Dict[str, Any]],
    legend_keyword: str,
) -> Dict[str, Any]:
    detected_total = len(detected_rows)
    keyword = legend_keyword.strip().lower()
    legend_total = 0
    for row in legend_rows:
        desc = str(row.get("description", "")).lower()
        if keyword and keyword not in desc:
            continue
        legend_total += int(row.get("count", 0))
    mismatch = legend_total - detected_total
    return {
        "legend_keyword": legend_keyword,
        "detected_total": detected_total,
        "legend_total": legend_total,
        "mismatch": mismatch,
        "matches": mismatch == 0,
    }


def write_summary_json(
    output_json: str,
    quality: Dict[str, Any],
    legend_rows: Sequence[Dict[str, Any]],
    comparison: Dict[str, Any],
) -> None:
    payload = {
        "quality": quality,
        "legend_rows": list(legend_rows),
        "legend_comparison": comparison,
    }
    with open(output_json, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2)


def _table_from_rows(rows: Sequence[Dict[str, Any]], columns: Sequence[str]) -> str:
    if not rows:
        return "<p>No rows detected.</p>"
    head = "".join(f"<th>{html.escape(c)}</th>" for c in columns)
    body_lines: List[str] = []
    for row in rows:
        status = str(row.get("status", ""))
        row_class = " class='diff-changed'" if status == "ambiguous" else ""
        cells = "".join(
            f"<td>{html.escape(str(row.get(c, '')))}</td>"
            for c in columns
        )
        body_lines.append(f"<tr{row_class}>{cells}</tr>")
    return f"<table><thead><tr>{head}</tr></thead><tbody>{''.join(body_lines)}</tbody></table>"


def write_universal_html_report(
    output_html: str,
    title: str,
    subtitle: str,
    rows: Sequence[Dict[str, Any]],
    legend_rows: Sequence[Dict[str, Any]],
    comparison: Dict[str, Any],
    quality: Dict[str, Any],
) -> None:
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    chips = (
        f"<span class='chip'>Detected: {quality.get('count', 0)}</span>"
        f"<span class='chip'>Certain: {quality.get('certain_count', 0)}</span>"
        f"<span class='chip'>Ambiguous: {quality.get('ambiguous_count', 0)}</span>"
        f"<span class='chip'>Legend: {comparison.get('legend_total', 0)}</span>"
        f"<span class='chip'>Mismatch: {comparison.get('mismatch', 0)}</span>"
        f"<span class='chip'>Generated: {stamp}</span>"
    )
    detected_table = _table_from_rows(
        rows,
        ["id", "x", "y", "radius", "text_confidence", "shape_confidence", "confidence", "status"],
    )
    legend_table = _table_from_rows(legend_rows, ["count", "description", "raw"])
    out_dir = Path(output_html).parent
    if str(out_dir):
        out_dir.mkdir(parents=True, exist_ok=True)
    html_text = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>{html.escape(title)}</title>
<style>
  body {{ font-family: 'Segoe UI', system-ui, Arial, sans-serif; background: #0b0b0f; color: #eaeaf0; padding: 24px; margin: 0; }}
  h1 {{ color: #8ed0ff; margin: 0 0 4px 0; }}
  h2 {{ color: #c0c0d0; border-bottom: 1px solid #2a2a34; padding-bottom: 6px; margin-top: 28px; }}
  .meta {{ color: #888; font-size: 13px; margin-bottom: 12px; }}
  .chip {{ display: inline-block; background: #1a1a22; border: 1px solid #2a2a34; padding: 3px 10px; border-radius: 999px; margin-right: 8px; font-size: 12px; }}
  table {{ border-collapse: collapse; width: 100%; margin-top: 8px; }}
  th, td {{ border: 1px solid #2a2a34; padding: 7px 10px; font-size: 13px; text-align: left; }}
  th {{ background: #171720; color: #b0b0c0; }}
  tr:nth-child(even) {{ background: #0f0f16; }}
  .diff-changed {{ background: #2a2a0a; }}
  .insights {{ background: #12121a; border: 1px solid #2a2a34; border-radius: 8px; padding: 12px 18px; margin-top: 8px; }}
</style>
</head>
<body>
<h1>{html.escape(title)}</h1>
<p class="meta">{html.escape(subtitle)} - {stamp}</p>
<div>{chips}</div>
<h2>Detected Symbols</h2>
{detected_table}
<h2>Legend Rows (Right Column OCR)</h2>
{legend_table}
<h2>Comparison</h2>
<div class="insights">
<p>Keyword: <code>{html.escape(str(comparison.get("legend_keyword", "")))}</code></p>
<p>Detected total: <b>{comparison.get("detected_total", 0)}</b></p>
<p>Legend total: <b>{comparison.get("legend_total", 0)}</b></p>
<p>Mismatch: <b>{comparison.get("mismatch", 0)}</b> ({'match' if comparison.get('matches') else 'review needed'})</p>
</div>
</body>
</html>"""
    Path(output_html).write_text(html_text, encoding="utf-8")
