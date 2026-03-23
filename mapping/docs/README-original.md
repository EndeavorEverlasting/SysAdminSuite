
# RPM Recon ΓÇö ZeroΓÇæRisk Printer Mapping Inventory
**Version:** v0.1.0 (Recon Alpha) ΓÇö generated 2025-09-29 19:32:31

This repository contains a controller/worker pair that performs a **readΓÇæonly inventory** of printer mappings on many Windows hosts, in parallel, with **graceful Ctrl+C** handling and a oneΓÇæpage HTML report.  
It **does not** change endpoint configuration. It stages a small worker on each host, runs once as **SYSTEM** via Task Scheduler, collects artifacts, and cleans up.

---

## Repo Layout (expected)
```
mapping/
Γö£ΓöÇ RPM-Recon.ps1                      # Controller (you run this)
Γö£ΓöÇ Map-Remote-MachineWide-Printers.ps1# Worker (staged on each host; read-only)
Γö£ΓöÇ csv/
Γöé  ΓööΓöÇ hosts.txt                       # One host per line; # comments allowed
ΓööΓöÇ logs/
   ΓööΓöÇ recon-YYYYMMDD-HHmmss/          # Per-run session folder with results
```

> Your uploaded files included these names, so this README assumes that layout. If paths differ in your repo, adjust the examples below accordingly.

---

## Quickstart (Controller box ΓÇö PowerShell 7, elevated)
```powershell
# From repo root or mapping folder
.\mapping\RPM-Recon.ps1 -HostsPath .\mapping\csv\hosts.txt `
                        -MaxParallel 12 `
                        -MaxWaitSeconds 45 `
                        -PollSeconds 3
```

**Outputs (per run)** will be written under `mapping\logs\recon-YYYYMMDD-HHmmss\`:
- **Session:** `Controller.log`, `CentralResults.csv` (if any), `index.html`
- **Per-host (if produced):** `Results.csv`, `Results.html`, `Preflight.csv`, `Run.log`

> The HTML report **only shows a download for CentralResults.csv if the file exists** (so you wonΓÇÖt see a broken link when no hosts produced artifacts).

---

## What It Does (Pipeline)
1. **Resolve** host ΓåÆ prefer FQDN (e.g., `HOST.domain`) for SMB/Scheduler consistency.
2. **Reachability check** ΓåÆ ping once; if down, log `OFFLINE` and continue.
3. **Stage worker** ΓåÆ copy to `\<fqdn>\C$\ProgramData\SysAdminSuite\Mapping\`.
4. **Schedule** oneΓÇætime SYSTEM task with explicit date/time (no `/Z` autoΓÇædelete).
5. **Kick & poll** ΓåÆ start task; poll for artifacts for up to `MaxWaitSeconds`.
6. **Collect** artifacts ΓåÆ pull back `Results.csv/html`, `Preflight.csv`, logs.
7. **RollΓÇæup** ΓåÆ union all `Results.csv` into `CentralResults.csv` if any exist.
8. **Report** ΓåÆ write `index.html` with chips + full controller log embedded.
9. **Cleanup** ΓåÆ remove remote task and staging dir (bestΓÇæeffort).

All stages emit **breadcrumbs** in `Controller.log` and to the console.

---

## CLI Parameters
- `-HostsPath <path>` **(required)**: Text file with one host per line; `#` = comment.
- `-MaxParallel <int>`: Degree of parallelism (default `12`). PowerShell 7 feature.
- `-MaxWaitSeconds <int>`: PerΓÇæhost polling budget (default `60`).
- `-PollSeconds <int>`: Poll cadence (default `3`).

---

## Requirements
- **PowerShell 7+** on the controller (for `ForEach-Object -Parallel`).
- Run the controller **as Administrator**.
- Your account must be local/domain admin on targets (admin shares & Task Scheduler).
- `Map-Remote-MachineWide-Printers.ps1` present in the `mapping` folder.

---

## Logging, HTML, and Graceful Ctrl+C
- **Controller.log** streams as the run progresses. If you hit **Ctrl+C**, the controller:
  - Flushes any inΓÇæmemory progress.
  - Writes whatever `CentralResults.csv` can be produced from existing artifacts.
  - Regenerates `index.html` so you can review partial results.
- **index.html** shows run time, host count, an optional `CentralResults.csv` chip (only when present), and the entire controller log for quick triage.

---

## Smoke Test (limit scope)
```powershell
Get-Content .\mapping\csv\hosts.txt |
  Where-Object { $_ -and $_ -notmatch '^\s*#' } |
  Select-Object -First 3 |
  Set-Content .\mapping\csv\hosts_smoke.txt

.\mapping\RPM-Recon.ps1 -HostsPath .\mapping\csv\hosts_smoke.txt -MaxParallel 3 -MaxWaitSeconds 25
```

---

## Known Quirks (and how this build handles them)
- **Scheduler XML EndBoundary errors** when using `schtasks /SC ONCE /Z` on some builds.  
  ΓåÆ This controller **avoids** `/Z` and sets an explicit start date/time.
- **Long `/TR` strings** (>261 chars) under SYSTEM can break PATH/working dir.  
  ΓåÆ Ensure the worker path is absolute and short; the controller uses absolute paths.
- **Parallel blocks & `$using:` quirks** in PS7.  
  ΓåÆ This build caches shared objects before entering `-Parallel` and avoids calling methods on `$using:` directly.
- **Kerberos ΓÇ£Target account name is incorrect.ΓÇ¥**  
  ΓåÆ Use FQDN for both the `\share` and the `/S` argument to `schtasks`. Verify DNS & SPNs.

---

## Troubleshooting OneΓÇæLiners
```powershell
$PSVersionTable.PSVersion.Major    # should be 7
Resolve-DnsName YOUR-HOST          # confirm FQDN
Test-Connection YOUR-HOST -Count 1 -Quiet
dir "\YOUR-HOST\C$"              # try FQDN from Resolve-DnsName if this fails
# Optional: map a credentialed drive when policy allows NTLM
$cred = Get-Credential
New-PSDrive -Name X -PSProvider FileSystem -Root "\YOUR-HOST\C$" -Credential $cred
dir X:\ProgramData
Remove-PSDrive X
```

---

## Output Contract
- **CentralResults.csv** = union of all perΓÇæhost `Results.csv` (if any).
- **Results.csv** schema is whatever your worker emits (readΓÇæonly inventory).
- **Controller.log** = authoritative trace (timestamps, host, stage, summary).
- **index.html** = singleΓÇæfile summary with chips + inline log for quick audits.

---

## Safety Notes
- Worker runs in **recon mode only** (no mapping changes).  
- Remote artifacts are cleaned after collection (bestΓÇæeffort; failures are logged).
- Partial successes are always preserved; failed hosts donΓÇÖt prevent rollΓÇæup.

---

## FAQ
**Q: The HTML shows ΓÇ£Central CSV: none.ΓÇ¥ Did I break something?**  
A: No. That simply means no host produced `Results.csv` within the poll window.

**Q: Can I extend the wait without flooding the network?**  
A: YesΓÇöraise `-MaxWaitSeconds`. Polling is lightweight and sleeps between checks.

**Q: IΓÇÖm on Windows PowerShell 5.x.**  
A: `-Parallel` is PS7ΓÇæonly. You can adapt the controller to serial execution, but expect longer runtimes.

---

## Changelog (this version)
- Guarded the HTML so the *CentralResults.csv* link appears **only** when the file exists.
- Polished logging flush order to ensure clean endΓÇæofΓÇærun (or Ctrl+C) output.

---

## License
Internal tooling ΓÇö adapt as needed.