# Go-Live Runbook

## Quick Start
1. Double-click **Run-Preflight.cmd**. Fix any warnings (use **New-SourcesTemplate.cmd** if prompted).
2. Double-click **Rebuild-FetchMap.cmd**.
3. Double-click **Test-Links.cmd**. If any `Status` ≠ 200, adjust `sources.csv` and repeat step 2.
4. Double-click **Fetch-DRYRUN.cmd**. If clean, double-click **Fetch.cmd**.
5. Double-click **Stage-To-Clients.cmd** (requires `Clients.txt`).
6. Double-click **ImpactS-Find.cmd**; review the CSV in `Logs\`.
7. Double-click **ImpactS-FixShortcuts.cmd** (first run is dry-run; edit script to remove `-WhatIf` to commit).
8. On a target PC, double-click **Install-On-This-PC.cmd**.

## Host Resolution
- Scripts read **RepoHost.txt** (if present) or the `REPO_HOST` environment variable.
- If neither is set, local fallback is `C:\SoftwareRepo`.
- On load of `GoLiveTools.ps1` you’ll see: `Using RepoRoot: <path>`.

## Logs
All wrappers write logs and exports to `.\Logs\`. Keep them for auditing.

## Known Gotchas We Already Solved
- Winget blocked → switched to vendor URLs with `sources.csv` → `fetch-map.csv`.
- GitHub tag mismatch (`v` vs none) → robust resolver tries both and exact-matches.
- PowerShell `$Host` collision → parameter renamed to `-RepoServer` internally.
- Missing files → `Preflight-Repo` warns loudly and `New-SourcesTemplate` scaffolds.
- Silent args / installer type confusion → `Fill-PackagesTypes` fingerprints and fills sane defaults.

## Files You Edit
- `sources.csv` (add or pin software; adjust `AssetRegex` and `Version`).
- `Clients.txt` (fleet list).
- `ImpactS-Paths.psd1` (old/new target directories for the shortcut fix).
- `RepoHost.txt` (optional depot host name).

Happy deployments.
