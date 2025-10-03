
---

## `mapping/README.md` (documentation you asked for)

````markdown
# RPM-Recon.ps1 — Zero-Risk Printer Mapping Recon

Inventories current printer mappings on many Windows hosts **without changing anything**.
It stages the existing worker `Map-Remote-MachineWide-Printers.ps1` on each target,
runs it as **SYSTEM** via Task Scheduler, polls for results, collects them locally,
and wipes the remote staging folder.

---

## Quickstart

```powershell
# From repo root or mapping folder (PowerShell 7, elevated)
.\mapping\RPM-Recon.ps1 -HostsPath .\mapping\csv\hosts.txt
````

* Hosts file: one hostname per line; blanks and `#` comments allowed.
* Outputs in `mapping\logs\recon-YYYYMMDD-HHmmss\`:

  * Per-host: `Results.html`, `Results.csv`, `Preflight.csv`, `Run.log`
  * Session: `Controller.log`, `CentralResults.csv`, `index.html` (clickable)

---

## Requirements

* **PowerShell 7+** (needed for `ForEach-Object -Parallel`)
* Run console **as Administrator** (create/delete remote scheduled tasks)
* Your account must be local/domain admin on targets (admin shares + Task Scheduler)
* File: `mapping\Map-Remote-MachineWide-Printers.ps1` present

---

## How it Works (Stages)

1. **Resolve name** → prefers FQDN (`dns.GetHostEntry`), falls back to short name
2. **Ping** → if unreachable → `[$target] OFFLINE`
3. **Stage worker** → `\\<fqdn>\C$\ProgramData\SysAdminSuite\Mapping\`
4. **Schedule once** (SYSTEM) → *explicit* `/SD` + `/ST` (no `/Z`)
5. **Poll** remote `logs\<stamp>` for artifacts
6. **Collect** into local session folder
7. **Cleanup** task + remote staging

All steps emit breadcrumbs into `Controller.log`:
`PING OK`, `COPY OK`, `TASK CREATED`, `POLLING …`, `COLLECTED`, or an `ERROR:` line.

---

## CLI Options

* `-HostsPath <path>` — required; txt list with one host per line
* `-MaxParallel <int>` — default 12; adjust to taste
* `-MaxWaitSeconds <int>` — default 60; per-host poll budget
* `-PollSeconds <int>` — default 3; poll cadence

---

## Common Pitfalls (and the fixes baked into this script)

* **“Expression is not allowed in a Using expression.”**
  You can’t call methods on `$using:bag` in a parallel block.
  *Fix:* cache it: `$bagRef = $using:bag`, then call `$bagRef.Add(...)`.

* **Do not use `$host` as a variable.**
  `$host` is a built-in, read-only automatic variable.
  *Fix:* this script uses `$target`.

* **`ForEach-Object -Parallel -ArgumentList` doesn’t exist.**
  *Fix:* pass values via `$using:`; this script does.

* **Task Scheduler `EndBoundary` XML error (with `/SC ONCE /Z`).**
  *Fix:* we **don’t** use `/Z` and we set **both** `/SD` and `/ST`.

* **SMB/Kerberos: “The target account name is incorrect.”**
  Usually short-name vs SPN mismatch, or DNS/CNAME.
  *Fix:* resolve FQDN and use it for `\\share` and `/S` in `schtasks`.

* **Copy-Item swallowed errors (looked like a hang).**
  *Fix:* file ops use `-ErrorAction Stop`, so failures hit `catch` and log.

---

## Troubleshooting Snippets

```powershell
# Confirm prereqs
$PSVersionTable.PSVersion.Major            # should be 7
Test-Path .\mapping\Map-Remote-MachineWide-Printers.ps1
Test-Path .\mapping\csv\hosts.txt

# Single-host smoke test
$h = 'YOUR-HOST'
Test-Connection $h -Count 1 -Quiet
Resolve-DnsName $h
dir "\\$h\C$\"        # if this fails, try FQDN from Resolve-DnsName

# Force a credentialed SMB drive (if policy allows NTLM)
$cred = Get-Credential
New-PSDrive -Name X -PSProvider FileSystem -Root "\\$h\C$" -Credential $cred
dir X:\ProgramData
Remove-PSDrive X
```

---

## Output You Can Rely On

* **Controller.log**: complete per-host trace with timings
* **CentralResults.csv**: union of all `Results.csv` files
* **index.html**: click-through browser view for quick audits

---

## Safety

* Zero configuration changes to endpoints (`-ListOnly -Preflight` only)
* Remote artifacts cleaned after collection
* Failures are logged; partial successes preserved

````

---

## Fast implementation guide (no fluff)

1) **Overwrite** `mapping\RPM-Recon.ps1` with the script above.  
2) **Save** `mapping\README.md` with the content above.  
3) **Verify**:
   ```powershell
   Test-Path .\mapping\Map-Remote-MachineWide-Printers.ps1
   Test-Path .\mapping\csv\hosts.txt
   $PSVersionTable.PSVersion.Major
````

4. **Run elevated** PowerShell 7:

   ```powershell
   cd "C:\Users\pa_rperez26\OneDrive - Northwell Health\Desktop\dev\SysAdminSuite"
   .\mapping\RPM-Recon.ps1 -HostsPath .\mapping\csv\hosts.txt
   ```
5. **Open** the generated `index.html` listed at the end of the run; check `Controller.log` for `PING OK / COPY OK / TASK CREATED / POLLING / COLLECTED`.

If the first host throws SMB/Kerberos shade, the log will say so. Use the README’s troubleshooting one-liners to confirm DNS/FQDN and admin share access, then rerun.
