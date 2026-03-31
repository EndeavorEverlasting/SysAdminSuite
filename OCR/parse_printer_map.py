#!/usr/bin/env python3
"""
Parse printer maps (PDF/image) into PrinterID,x,y rows.
"""

from map_parse_core import (
    GREEN_RANGES,
    compare_detected_to_legend,
    detect_legend_rows,
    draw_overlay,
    extract_entities_detailed,
    load_map_bgr,
    parse_args_common,
    summarize_detailed_quality,
    write_entities_detailed_csv,
    write_summary_json,
    write_universal_html_report,
)
import cv2
from pathlib import Path


def main() -> None:
    ap = parse_args_common("Parse printer map")
    ap.set_defaults(expected_min=1, expected_max=99)
    ap.add_argument("--confidence-threshold", type=float, default=0.75)
    ap.add_argument("--legend-right-ratio", type=float, default=0.33)
    ap.add_argument("--legend-keyword", default="printer")
    ap.add_argument("--out-summary-json", default="")
    args = ap.parse_args()

    bgr = load_map_bgr(args.map, dpi=args.dpi)
    rows = extract_entities_detailed(
        bgr=bgr,
        ranges=GREEN_RANGES,
        expected_min=args.expected_min,
        expected_max=args.expected_max,
        min_radius=args.min_radius,
        max_radius=args.max_radius,
        confidence_threshold=args.confidence_threshold,
    )
    write_entities_detailed_csv(rows, args.out_csv, "PrinterID")

    if args.out_overlay:
        overlay_rows = [(int(r["id"]), int(r["x"]), int(r["y"])) for r in rows]
        overlay = draw_overlay(bgr, overlay_rows, (0, 255, 0), "Printers")
        cv2.imwrite(args.out_overlay, overlay)

    quality = summarize_detailed_quality(rows)
    legend_rows = detect_legend_rows(bgr, right_ratio=args.legend_right_ratio)
    comparison = compare_detected_to_legend(
        rows, legend_rows, legend_keyword=args.legend_keyword
    )
    if args.out_summary_json:
        write_summary_json(args.out_summary_json, quality, legend_rows, comparison)
    out_html = args.out_html if args.out_html else str(Path(args.out_csv).with_suffix(".html"))
    write_universal_html_report(
        output_html=out_html,
        title="Printer Map Parse Report",
        subtitle=args.map,
        rows=rows,
        legend_rows=legend_rows,
        comparison=comparison,
        quality=quality,
    )
    print(
        "printer_parse "
        f"count={quality['count']} "
        f"certain={quality['certain_count']} "
        f"ambiguous={quality['ambiguous_count']} "
        f"legend_total={comparison['legend_total']} "
        f"mismatch={comparison['mismatch']} "
        f"out={args.out_csv} "
        f"html={out_html}"
    )


if __name__ == "__main__":
    main()
