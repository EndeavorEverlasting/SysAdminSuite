
#!/usr/bin/env python3
"""
build_host_unc_csv.py
---------------------
Join nearest mapping (WorkstationID->PrinterID) with a printer lookup (PrinterID->UNC)
and output a Host->UNC mapping CSV for your PowerShell mapper.

Inputs:
  nearest.csv          (WorkstationID,PrinterID,DistancePx)  # from locus_mapping_ocr.py
  printer_lookup.csv   (PrinterID,UNC)                       # you fill this once based on PM's names

Output:
  host_printers.csv    (Host,UNC)
    where Host is WLS111WCC<WorkstationID> (edit the prefix as needed)
"""

import argparse, pandas as pd

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nearest", default="locus-nearest.csv")
    ap.add_argument("--lookup",  default="printer_lookup.csv")
    ap.add_argument("--host-prefix", default="WLS111WCC", help="Hostname prefix before the workstation number")
    ap.add_argument("--out", default="host_printers.csv")
    args = ap.parse_args()

    nn  = pd.read_csv(args.nearest)
    lut = pd.read_csv(args.lookup)
    df = nn.merge(lut, on="PrinterID", how="left")
    df["WorkstationID_num"] = pd.to_numeric(df["WorkstationID"], errors="coerce")
    df = df[df["WorkstationID_num"].notna()].copy()
    df["Host"] = df["WorkstationID_num"].astype(int).apply(lambda n: f"{args.host_prefix}{n}")
    out = df[["Host","UNC"]].dropna().drop_duplicates().sort_values("Host")
    out.to_csv(args.out, index=False)
    print(f"Wrote {len(out)} rows to {args.out}")

if __name__ == "__main__":
    main()