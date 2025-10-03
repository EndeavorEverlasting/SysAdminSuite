
# Runbook — Implement Recon Across 164 Devices (No config changes)

This runbook drives your existing **RPM-Recon.ps1** in safe batches and gives you
a predictable audit trail. It does **not** change the recon logic—only orchestration.

## 0) Preconditions (once)
- PowerShell **7+**, elevated
- Repo layout as documented in README
- `mapping\RPM-Recon.ps1` present and working
- `mapping\csv\hosts.txt` contains **all 164 hosts**, one per line (`#` for comments)

## 1) Download the helper
- Save **Run-164.ps1** next to `mapping/` (repo root or inside `mapping/` both OK).

## 2) Dry-run sanity (3 hosts)
```powershell
Get-Content .\mapping\csv\hosts.txt | ? { $_ -and $_ -notmatch '^\s*#' } | select -First 3 |
  Set-Content .\mapping\csv\hosts_smoke.txt
.\mapping\RPM-Recon.ps1 -HostsPath .\mapping\csv\hosts_smoke.txt -MaxParallel 6 -MaxWaitSeconds 25 -PollSeconds 3
```

## 3) Full 164 rollout (batched)
Recommended starting values: **BatchSize=24**, **MaxParallel=12**, **Delay=20s**
```powershell
# From repo root or mapping folder
.\Run-164.ps1 -HostsPath .\mapping\csv\hosts.txt -BatchSize 24 -MaxParallel 12 -MaxWaitSeconds 45 -PollSeconds 3 -DelayBetweenBatches 20
```

What this does:
- Splits the 164 hosts into ~7 batches (`hosts_batch-001.txt`, …).
- Calls your **RPM-Recon.ps1** for each batch.
- Rolls up any per-batch `CentralResults.csv` into **logs\MasterResults.csv**.
- Prints a summary and where to find session folders.

## 4) Interpreting results
- Per batch, open `mapping\logs\recon-YYYYMMDD-HHmmss\index.html`.
- If **CentralResults.csv** is missing: no host produced `Results.csv` in-window; increase `-MaxWaitSeconds` and re-run that batch file.
- The **MasterResults.csv** in `mapping\logs` is the union of all batch runs during this orchestration.

## 5) Reruns / Recovery
- You can re-run a specific batch only:
```powershell
.\mapping\RPM-Recon.ps1 -HostsPath .\mapping\csv\hosts_batch-003.txt -MaxParallel 12 -MaxWaitSeconds 60
```
- Hosts can appear in multiple batches safely; recon is read-only.
- If Kerberos/SPN errors show up, swap short names for FQDNs in `hosts.txt`.

## 6) Tuning heuristics
- Lots of 'OFFLINE' or `COPY` errors → drop `-MaxParallel` to 8 and add delay (30–45s).
- Busy endpoints, slow artifact writes → raise `-MaxWaitSeconds` to 60–90.
- Controller CPU pinned → lower `-MaxParallel` per batch.

---

**Tip:** Commit `hosts_batch-*.txt` and `logs\MasterResults.csv` with your CHANGELOG note for a crisp audit trail of the 164-device implementation.
