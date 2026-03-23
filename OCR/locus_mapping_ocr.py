
#!/usr/bin/env python3

"""
locus_mapping_ocr.py
--------------------
Extract workstation (red circles) and printer (green circles) numbers & coordinates
from annotated floorplan images, then compute nearest-printer mapping per workstation.

Requirements (install once):
    pip install opencv-python-headless pillow pytesseract numpy pandas
And install Tesseract OCR engine:
    - Windows: https://github.com/UB-Mannheim/tesseract/wiki
    - macOS (brew): brew install tesseract
    - Linux (apt):  sudo apt-get install tesseract-ocr

Usage (example):
    python locus_mapping_ocr.py \
        --workstations "workstations.png" \
        --printers "printers.png" \
        --rotate-ws 0 \
        --rotate-pr 0 \
        --out-prefix "ls111"

Outputs:
    <out>-workstations.csv   (WorkstationID,x,y)
    <out>-printers.csv       (PrinterID,x,y)
    <out>-nearest.csv        (WorkstationID,PrinterID,DistancePx)
    <out>-overlay-ws.png     (debug overlay of detected WS)
    <out>-overlay-pr.png     (debug overlay of detected PR)
"""

import argparse, re, os
import cv2, numpy as np, pytesseract, pandas as pd
from math import hypot

RED_RANGES = [
    (np.array([0, 100, 100]),  np.array([10, 255, 255])),
    (np.array([160, 100, 100]), np.array([179, 255, 255]))
]
GREEN_RANGES = [(np.array([35, 40, 40]), np.array([85, 255, 255]))]

def rotate_image(img, degrees):
    if degrees % 360 == 0: return img
    if degrees % 360 == 90:  return cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
    if degrees % 360 == 180: return cv2.rotate(img, cv2.ROTATE_180)
    if degrees % 360 == 270: return cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)
    # arbitrary angle:
    h,w = img.shape[:2]
    M = cv2.getRotationMatrix2D((w//2,h//2), degrees, 1.0)
    return cv2.warpAffine(img, M, (w,h))

def mask_color(hsv, ranges):
    mask = None
    for lo, hi in ranges:
        m = cv2.inRange(hsv, lo, hi)
        m = cv2.medianBlur(m, 5)
        mask = m if mask is None else cv2.bitwise_or(mask, m)
    kernel = np.ones((3,3), np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    return mask

def ocr_digits(img):
    # img: BGR small ROI presumed to contain a number
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (3,3), 0)
    thr  = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C,
                                 cv2.THRESH_BINARY_INV, 31, 10)
    up   = cv2.resize(thr, None, fx=6, fy=6, interpolation=cv2.INTER_CUBIC)
    cfg  = "--psm 7 -c tessedit_char_whitelist=0123456789"
    text = pytesseract.image_to_string(up, config=cfg)
    text = re.sub(r"[^\d]", "", text)
    return text

def extract_points(bgr, ranges, expected_min=None, expected_max=None, min_r=10, max_r=60):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    mask = mask_color(hsv, ranges)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    raw = []
    for cnt in contours:
        (x, y), radius = cv2.minEnclosingCircle(cnt)
        if radius < min_r or radius > max_r: 
            continue
        x, y, r = int(x), int(y), int(radius)
        pad = int(r * 1.7)
        x1, y1, x2, y2 = max(0, x-pad), max(0, y-pad), min(bgr.shape[1], x+pad), min(bgr.shape[0], y+pad)
        roi = bgr[y1:y2, x1:x2]
        txt = ocr_digits(roi)
        if not txt: 
            continue
        try:
            num = int(txt)
        except:
            continue
        # normalize to expected range
        if expected_min is not None and expected_max is not None:
            if num < expected_min:
                if num < 100 and expected_min >= 100:
                    num = 100 + num
            if num > expected_max:
                s = str(num)
                if expected_max >= 100:
                    num = int(s[-3:]) if len(s) >= 3 else int(s)
                else:
                    num = int(s[-2:]) if len(s) >= 2 else int(s)
        raw.append((num, x, y, r))
    # dedupe by proximity
    raw.sort(key=lambda t: (t[0], t[1], t[2]))
    taken = [False]*len(raw)
    points = []
    for i,(ni,xi,yi,ri) in enumerate(raw):
        if taken[i]: 
            continue
        group = [(ni,xi,yi,ri)]
        taken[i] = True
        for j,(nj,xj,yj,rj) in enumerate(raw):
            if i==j or taken[j]: 
                continue
            if abs(xi-xj) <= 26 and abs(yi-yj) <= 26:
                group.append((nj,xj,yj,rj))
                taken[j] = True
        nums = [g[0] for g in group]
        best_num = max(set(nums), key=nums.count)
        xs = sorted([g[1] for g in group])
        ys = sorted([g[2] for g in group])
        points.append((best_num, xs[len(xs)//2], ys[len(ys)//2]))
    return points

def nearest(ws_points, pr_points):
    rows = []
    for wid, wx, wy in ws_points:
        best = None
        best_d = 1e18
        best_pid = None
        for pid, px, py in pr_points:
            d = hypot(wx-px, wy-py)
            if d < best_d:
                best_d, best, best_pid = d, (px,py), pid
        rows.append((wid, best_pid, int(round(best_d))))
    return rows

def draw_overlay(bgr, points, color, label):
    out = bgr.copy()
    for pid,x,y in points:
        cv2.circle(out, (x,y), 16, color, 2)
        cv2.putText(out, str(pid), (x-14, y-20), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2, cv2.LINE_AA)
    cv2.putText(out, label, (15, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2, cv2.LINE_AA)
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workstations", required=True, help="Path to annotated workstation map image (red circles)")
    ap.add_argument("--printers",     required=True, help="Path to annotated printer map image (green circles)")
    ap.add_argument("--rotate-ws",    type=int, default=0, help="Rotate WS image by 0/90/180/270")
    ap.add_argument("--rotate-pr",    type=int, default=0, help="Rotate PR image by 0/90/180/270")
    ap.add_argument("--out-prefix",   default="locus", help="Prefix for output files")
    args = ap.parse_args()

    ws_bgr = cv2.imread(args.workstations)
    pr_bgr = cv2.imread(args.printers)
    if ws_bgr is None: raise SystemExit(f"Cannot read workstation image: {args.workstations}")
    if pr_bgr is None: raise SystemExit(f"Cannot read printer image: {args.printers}")

    ws_bgr = rotate_image(ws_bgr, args.rotate_ws)
    pr_bgr = rotate_image(pr_bgr, args.rotate_pr)

    # Extract points
    ws_points = extract_points(ws_bgr, RED_RANGES, expected_min=100, expected_max=200, min_r=9, max_r=60)
    pr_points = extract_points(pr_bgr, GREEN_RANGES, expected_min=1, expected_max=60, min_r=9, max_r=60)

    # Save overlays
    ov_ws = draw_overlay(ws_bgr, ws_points, (0,0,255), "Workstations")
    ov_pr = draw_overlay(pr_bgr, pr_points, (0,255,0), "Printers")
    cv2.imwrite(f"{args.out_prefix}-overlay-ws.png", ov_ws)
    cv2.imwrite(f"{args.out_prefix}-overlay-pr.png", ov_pr)

    # Save CSVs
    ws_df = pd.DataFrame(ws_points, columns=["WorkstationID","x","y"]).sort_values("WorkstationID")
    pr_df = pd.DataFrame(pr_points, columns=["PrinterID","x","y"]).sort_values("PrinterID")
    ws_df.to_csv(f"{args.out_prefix}-workstations.csv", index=False)
    pr_df.to_csv(f"{args.out_prefix}-printers.csv", index=False)

    # Nearest mapping
    nearest_rows = nearest(ws_points, pr_points)
    nn_df = pd.DataFrame(nearest_rows, columns=["WorkstationID","PrinterID","DistancePx"]).sort_values("WorkstationID")
    nn_df.to_csv(f"{args.out_prefix}-nearest.csv", index=False)

    print(f"Detected workstations: {len(ws_df)}  -> {args.out_prefix}-workstations.csv")
    print(f"Detected printers:     {len(pr_df)}  -> {args.out_prefix}-printers.csv")
    print(f"Nearest mapping saved:              -> {args.out_prefix}-nearest.csv")
    print(f"Overlays: {args.out_prefix}-overlay-ws.png, {args.out_prefix}-overlay-pr.png")

if __name__ == "__main__":
    main()