# WAB Test Readiness

## Purpose

This document defines how SysAdminSuite should be tested on the WAB path before anyone attempts printer mapping, UNC, RPC, DNS, or other network-dependent features.

The immediate field lesson is simple: a tool can report `running` while every network result is still useless because the machine is on the wrong network. That is an environment miss, not automatically a product failure.

## Current field observation

Date: 2026-05-22

Observed posture:

- SysAdminSuite reported `running`.
- Results came back offline because the user/device was on the guest network.
- Network-feature validation is therefore inconclusive.
- Local launch and offline-safe behavior may still be valid evidence.
- Printer/network features must not be judged until the test host is on the correct enterprise network, VPN, or authorized test segment.

## Core rule

Do not test network features until the WAB host passes preflight.

`running` only proves process startup. It does not prove network access, printer reachability, UNC access, RPC availability, DNS resolution, admin share access, or host eligibility.

## Test phases

### Phase 0: Repo readiness

Run these from the repo root before field testing:

```powershell
# PowerShell script health
.\tools\Test-ScriptHealth.ps1

# Pester suite when Pester 5 is available
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1

# Managed tests when the .NET SDK is available
dotnet test .\SysAdminSuite.sln -c Release
```

Expected result:

- Script parsing passes.
- Encoding/BOM checks pass.
- Pester failures are reviewed as product failures only if the local environment supports the tested path.
- .NET failures are reviewed as product failures only if the SDK and restore path are available.

### Phase 1: Local smoke test on WAB

This phase proves the tool can launch and produce local artifacts without touching the network.

```powershell
# GUI launch smoke test
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\GUI\Start-SysAdminSuiteGui.ps1

# QR task list smoke test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\QRTasks\Invoke-TechTask.ps1 -Task ?

# Local network snapshot only
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\QRTasks\Invoke-TechTask.ps1 -Task NetworkInfo
```

PS-independent dashboard host (no `powershell.exe`, no Python; see [GUI_HOST_MIGRATION.md](GUI_HOST_MIGRATION.md)):

```bat
:: Direct
Launch-SysAdminSuiteDashboard.Host.bat

:: Via runtime menu option [3]
Launch-SysAdminSuite-Runtime.bat
```

Expected smoke result: tray icon appears, browser opens `http://127.0.0.1:5000/dashboard/`, Stop from tray frees the port. Classify success as `OK_LOCAL_SMOKE`.

Evidence to save:

- Screenshot showing the GUI opened.
- The text output from `NetworkInfo`.
- Any generated Desktop artifact from the QR task runner.
- Exact command used.
- Hostname, username context, PowerShell version, and whether the session was elevated.

### Phase 2: Network preflight gate

Before printer mapping, remote probes, or host reachability tests, record the network posture.

```powershell
ipconfig /all
hostname
whoami
nltest /dsgetdc:nslijhs.net
nslookup SWBPNHPHPS01V
Test-NetConnection SWBPNHPHPS01V -Port 445
Test-NetConnection SWBPNHPHPS01V -Port 135
```

Pass criteria:

- Device is not on guest Wi-Fi for enterprise-target testing.
- DNS resolves expected internal hosts.
- Required print servers resolve.
- SMB/445 is reachable where UNC mapping is required.
- RPC/135 is reachable where scheduled task or remote management paths are required.
- Domain/controller lookup behaves as expected for the test environment.

Fail posture:

If these fail while the host is on guest network, mark the result as:

`ENVIRONMENT_BLOCKED_GUEST_NETWORK`

Do not mark it as a SysAdminSuite failure.

### Phase 2b: Naabu CDN-safe reachability (authorized network only)

After Phase 2 passes, validate the naabu pipeline on an **approved small host list** (not guest network). Follow low-noise survey discipline: AD-derived targets first, `-silent` for local output hygiene, `-ec` to avoid CDN/cloud edge waste, JSON for parser-facing output, no target-side writes. See [`NAABU_CYBERNET_PROFILES.md`](NAABU_CYBERNET_PROFILES.md), [`LOW_NOISE_SURVEY_DOCTRINE.md`](LOW_NOISE_SURVEY_DOCTRINE.md), and the doctrine profile contract [`../survey/naabu_profiles.json`](../survey/naabu_profiles.json).

```bash
bash survey/sas-ensure-naabu.sh
bash survey/sas-run-naabu-pipeline.sh --site SSUH --profile keyports_cybernet_json \
  --list logs/targets/SSUH_confirm_hosts.txt --out logs/nmap/SSUH_confirm.json --pipe-followup
bash survey/sas-cybernet-subnet-survey.sh --site SSUH --run-id <run-id> --mode parse-naabu-only
bash survey/sas-cybernet-subnet-survey.sh --site SSUH --run-id <run-id> --mode package-only --manifest survey/output/cybernet_targets_resolved.csv
```

Pass criteria:

- `bin/naabu.exe` installs via GitHub release (Northwell: no winget).
- `logs/nmap/SSUH_*_windows_ports_naabu.json` non-empty on live internal host.
- `*_followup.jsonl` contains `cybernet_signal` when `--pipe-followup` used.
- `run_dir/resolver/<site>_naabu_reachability.csv` exists after parse.
- `PACKAGE_MANIFEST.txt` lists naabu logs + reachability CSV.

Fail posture on guest network: `ENVIRONMENT_BLOCKED_GUEST_NETWORK`. Npcap/admin failures: `ENVIRONMENT_BLOCKED_POLICY`.

### Phase 3: Read-only network recon

Only after Phase 2 passes:

```powershell
# Read-only recon against smoke hosts
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Mapping\Controllers\RPM-Recon.ps1 -HostsPath .\Mapping\Config\hosts_smoke.txt
```

Result classification:

| Result | Meaning | Action |
| --- | --- | --- |
| `OK_LOCAL_SMOKE` | GUI/local tasks run without network dependency | Safe to proceed to network preflight |
| `ENVIRONMENT_BLOCKED_GUEST_NETWORK` | Host is on guest or otherwise isolated network | Move to correct network, then retest |
| `ENVIRONMENT_BLOCKED_POLICY` | Execution policy, AppLocker, permissions, or endpoint controls block the test | Document policy and pivot to compiled/native path if needed |
| `NETWORK_PREFLIGHT_FAILED` | Correct network claimed, but DNS/ports/UNC fail | Fix network posture before testing product code |
| `PRODUCT_FAILURE` | Environment is valid and supported, but SysAdminSuite logic fails | Open bug with command, output, artifact, and expected behavior |
| `INCONCLUSIVE` | Evidence is incomplete | Retest with full transcript and screenshots |

## Minimum evidence for PRs and issues

Every WAB/network test issue should include:

- Branch or commit SHA tested.
- Machine/network posture: guest, enterprise wired, enterprise Wi-Fi, VPN, or lab.
- Whether the session was elevated.
- PowerShell version.
- Exact command.
- Raw output.
- Artifact paths created.
- Result classification from the table above.

## Agent F — Low-Noise Survey Doctrine

Purpose:
Codifies low-noise Naabu/Cybernet survey profiles:
- AD-derived targets first
- -silent always for local output hygiene
- -ec to avoid CDN/cloud firewall waste where appropriate
- JSON for parser-facing outputs
- TXT/stdout only for raw pipeline handoff
- UDP only by justified profile
- no target-side writes or scripts
- no live field execution in this lane

## Do not skip this

No feature work should proceed from an offline guest-network result. That is how ghosts get promoted to architecture.
