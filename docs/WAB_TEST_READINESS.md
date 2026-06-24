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

#### Hard stop — guest or non-corp network

If Phase 2 preflight fails while the host is on guest Wi-Fi or another non-corp network:

```text
Classification: ENVIRONMENT_BLOCKED_GUEST_NETWORK
Action: stop, do not scan
```

Do not run naabu, nmap confirm-windows, subnet discovery, or CIDR sweeps until the host is on an authorized enterprise wired, enterprise Wi-Fi, VPN, or lab segment and preflight passes.

### Phase 2b: Naabu CDN-safe reachability (authorized network only)

After Phase 2 passes, validate the naabu pipeline on an **AD-derived small host list** (not guest network). See [`NAABU_CYBERNET_PROFILES.md`](NAABU_CYBERNET_PROFILES.md) and [`../logs/targets/README.md`](../logs/targets/README.md).

**Target population doctrine:**

```text
AD registered Cybernet population = target population source
logs/targets/                     = local gitignored AD-derived target store
confirm-windows host file         = derived subset from AD export
naabu/nmap                        = reachability validation only
followup/CIM/WMI/SCCM/manual      = identity/serial proof where approved
```

Place AD exports under `logs/targets/`. Derive a plain-text confirm list (one host per line, no CIDR). Do not use naabu/nmap discovery as population truth.

```bash
bash survey/sas-ensure-naabu.sh

# AD export → logs/targets/SSUH_cybernet_registered.* → logs/targets/SSUH_confirm_hosts.txt

bash survey/sas-cybernet-subnet-survey.sh --site SSUH --run-id <run-id> \
  --mode confirm-windows --confirm-tool naabu \
  --host-file logs/targets/SSUH_confirm_hosts.txt --pipe-followup

bash survey/sas-cybernet-subnet-survey.sh --site SSUH --run-id <run-id> --mode parse-naabu-only

bash survey/sas-cybernet-subnet-survey.sh --site SSUH --run-id <run-id> --mode package-only \
  --manifest survey/fixtures/cybernet_subnet_survey/cybernet_targets_resolved.sample.csv
```

Use a site-specific resolved manifest from field output when available; the fixture path above is synthetic for contract/dev prep only.

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

## Do not skip this

No feature work should proceed from an offline guest-network result. That is how ghosts get promoted to architecture.
