import cv2
import numpy as np
import pytesseract
import re
import pandas as pd
from math import hypot
from collections import defaultdict
from caas_jupyter_tools import display_dataframe_to_user

# Paths
printer_map_img_path = "/mnt/data/7df2b36e-17e2-46a3-9242-dc72308dc46b.png"
workstation_map_img_path = "/mnt/data/265e4c39-3bde-4d9a-9419-a4f42766bfb6.png"

# Color ranges (HSV)
RED_RANGES = [
    (np.array([0, 100, 100]),  np.array([10, 255, 255])),
    (np.array([160, 100, 100]), np.array([179, 255, 255]))
]
GREEN_RANGES = [(np.array([35, 40, 40]), np.array([85, 255, 255]))]

def mask_color(hsv, ranges):
    mask = None
    for lo, hi in ranges:
        m = cv2.inRange(hsv, lo, hi)
        m = cv2.medianBlur(m, 5)
        mask = m if mask is None else cv2.bitwise_or(mask, m)
    # Morphological opening to remove noise
    kernel = np.ones((3,3), np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    return mask

def find_circles_and_ocr(img, ranges, expected_min=None, expected_max=None, label_kind="workstation"):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    mask = mask_color(hsv, ranges)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    blobs = []
    for cnt in contours:
        (x, y), radius = cv2.minEnclosingCircle(cnt)
        if radius < 9 or radius > 60:
            continue
        x, y, r = int(x), int(y), int(radius)
        pad = int(r * 1.7)
        x1, y1, x2, y2 = max(0, x-pad), max(0, y-pad), min(img.shape[1], x+pad), min(img.shape[0], y+pad)
        roi = img[y1:y2, x1:x2]
        # Preprocess for OCR: grayscale, threshold
        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (3,3), 0)
        thr = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C,
                                    cv2.THRESH_BINARY_INV, 31, 10)
        # Upscale
        up = cv2.resize(thr, None, fx=6, fy=6, interpolation=cv2.INTER_CUBIC)
        # OCR
        cfg = "--psm 7 -c tessedit_char_whitelist=0123456789"
        text = pytesseract.image_to_string(up, config=cfg)
        text = re.sub(r"[^\d]", "", text)
        if not text:
            continue
        try:
            num = int(text)
        except ValueError:
            continue
        # Normalize
        if expected_min is not None and expected_max is not None:
            if num < expected_min:
                # If it's 0-99 and we expect 100+, try to promote to 100-199
                if num < 100 and expected_min >= 100:
                    num = 100 + num
            if num > expected_max:
                # If it's too large, take the last 2 or 3 digits
                s = str(num)
                if expected_max >= 100:
                    num = int(s[-3:]) if len(s) >= 3 else int(s)
                else:
                    num = int(s[-2:]) if len(s) >= 2 else int(s)
        blobs.append((num, x, y, r))
    return blobs

def dedupe_by_proximity(blobs, radius_px=25):
    # blobs: list of (num, x, y, r)
    if not blobs:
        return []
    # cluster by proximity
    taken = [False]*len(blobs)
    clusters = []
    for i,(ni,xi,yi,ri) in enumerate(blobs):
        if taken[i]: continue
        group = [(ni,xi,yi,ri)]
        taken[i] = True
        for j,(nj,xj,yj,rj) in enumerate(blobs):
            if i==j or taken[j]: continue
            if abs(xi-xj) <= radius_px and abs(yi-yj) <= radius_px:
                group.append((nj,xj,yj,rj))
                taken[j] = True
        # choose representative: majority number; else median of numbers
        nums = [g[0] for g in group]
        # majority vote
        best_num = max(set(nums), key=nums.count)
        # median coordinates
        xs = sorted([g[1] for g in group])
        ys = sorted([g[2] for g in group])
        rep = (best_num, xs[len(xs)//2], ys[len(ys)//2])
        clusters.append(rep)
    return clusters

# Load images
printer_img = cv2.imread(printer_map_img_path)
work_img = cv2.imread(workstation_map_img_path)

# Some maps might be rotated; try both original and 90deg cw, take the one with more blobs
def process_with_rotations(img, ranges, expected_min, expected_max, kind):
    best = []
    best_rot = 0
    cur = find_circles_and_ocr(img, ranges, expected_min, expected_max, kind)
    if len(cur) > len(best):
        best = cur; best_rot = 0
    # rotate 90 cw
    rot90 = cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
    cur = find_circles_and_ocr(rot90, ranges, expected_min, expected_max, kind)
    if len(cur) > len(best):
        best = [(n, y, rot90.shape[0]-x, r) for (n,x,y,r) in cur]; best_rot = 90  # map back approx
    # rotate 180
    rot180 = cv2.rotate(img, cv2.ROTATE_180)
    cur = find_circles_and_ocr(rot180, ranges, expected_min, expected_max, kind)
    if len(cur) > len(best):
        best = [(n, rot180.shape[1]-x, rot180.shape[0]-y, r) for (n,x,y,r) in cur]; best_rot = 180
    # rotate 270
    rot270 = cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)
    cur = find_circles_and_ocr(rot270, ranges, expected_min, expected_max, kind)
    if len(cur) > len(best):
        best = [(n, rot270.shape[1]-y, x, r) for (n,x,y,r) in cur]; best_rot = 270
    return best, best_rot

# Workstations expect ~100-160
ws_blobs, ws_rot = process_with_rotations(work_img, RED_RANGES, 100, 200, "workstation")
pr_blobs, pr_rot = process_with_rotations(printer_img, GREEN_RANGES, 1, 50, "printer")

ws_dedup = dedupe_by_proximity(ws_blobs, radius_px=28)
pr_dedup = dedupe_by_proximity(pr_blobs, radius_px=28)

# Build dataframes
ws_df = pd.DataFrame(ws_dedup, columns=["WorkstationID","x","y"]).sort_values("WorkstationID").reset_index(drop=True)
pr_df = pd.DataFrame(pr_dedup, columns=["PrinterID","x","y"]).sort_values("PrinterID").reset_index(drop=True)

# Save and display
ws_csv = "/mnt/data/workstations_detected.csv"
pr_csv = "/mnt/data/printers_detected.csv"
ws_df.to_csv(ws_csv, index=False)
pr_df.to_csv(pr_csv, index=False)

display_dataframe_to_user("Detected Workstations (preview)", ws_df.head(30))
display_dataframe_to_user("Detected Printers (preview)", pr_df.head(30))

ws_count = len(ws_df)
pr_count = len(pr_df)
(ws_count, ws_rot, pr_count, pr_rot, ws_csv, pr_csv)
