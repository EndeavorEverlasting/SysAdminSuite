#!/usr/bin/env python3
"""
Parse printer maps (PDF/image) into PrinterID,x,y rows.
"""

from map_parse_core import (
    GREEN_RANGES,
    draw_overlay,
    extract_entities,
    load_map_bgr,
    parse_args_common,
    summarize_quality,
    write_entities_csv,
)
import cv2


def main() -> None:
    ap = parse_args_common("Parse printer map")
    ap.set_defaults(expected_min=1, expected_max=99)
    args = ap.parse_args()

    bgr = load_map_bgr(args.map, dpi=args.dpi)
    rows = extract_entities(
        bgr=bgr,
        ranges=GREEN_RANGES,
        expected_min=args.expected_min,
        expected_max=args.expected_max,
        min_radius=args.min_radius,
        max_radius=args.max_radius,
    )
    write_entities_csv(rows, args.out_csv, "PrinterID")

    if args.out_overlay:
        overlay = draw_overlay(bgr, rows, (0, 255, 0), "Printers")
        cv2.imwrite(args.out_overlay, overlay)

    quality = summarize_quality(rows)
    print(f"printer_parse count={quality['count']} distinct_ids={quality['distinct_ids']} out={args.out_csv}")


if __name__ == "__main__":
    main()
