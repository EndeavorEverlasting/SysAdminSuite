# Agent Instructions for SysAdminSuite

## Language Hierarchy

SysAdminSuite targets both Northwell-specific Linux environments and general Windows corporate
environments. SysAdminSuite is now a **Bash-first SysAdmin suite** for Northwell-targeted field work.
The tooling hierarchy is:

1. **Bash** — primary for new operational work (survey, audit, transport, preflight)
2. **PowerShell** — active Windows tooling; used in real corporate deployments daily
3. **Linux native** (dig, ping, nc, arp, etc.) — quick checks without suite scripts
4. **C** — planned for performance-critical probe components
5. **Rust** — planned for systems-level tooling
6. **Lua** — planned for lightweight scripting and configuration

This hierarchy exists now and will grow. Agents MUST NOT rearrange or collapse it.

---

## Dashboard field entry (web UI)

For lay users opening the **web dashboard**, the front door is a double-click launcher — not CLI.

| User type | Double-click |
|-----------|--------------|
| Field user | `START-HERE-SysAdminSuite-Dashboard.bat` (canonical; `.cmd` aliases exist for compatibility) |
| IT / developer | `Launch-SysAdminSuiteDashboard.Host.bat` |

Canonical agent reference: [`docs/DASHBOARD_ENTRYPOINT.md`](docs/DASHBOARD_ENTRYPOINT.md).

First-run dependency bootstrap reference: [`docs/DASHBOARD_DEPENDENCY_BOOTSTRAP.md`](docs/DASHBOARD_DEPENDENCY_BOOTSTRAP.md).

Planned `.exe` shortcut sprint: [`docs/DASHBOARD_EXE_FUTURE_SPRINT.md`](docs/DASHBOARD_EXE_FUTURE_SPRINT.md).

Do **not** direct field users to `python3 -m http.server`, raw `dotnet` commands, or Bash survey scripts as the default dashboard path.

---

## CRITICAL — PowerShell Is NOT Dead Code

**PowerShell scripts in this repository are active, production-relevant tooling.**

Many organisations — including Northwell and the broader Windows enterprise space — run
PowerShell in their environments every single day. These scripts handle WMI queries, hardware
inventory, printer mapping, Active Directory lookups, and deployment tracking. They cannot be
replaced by a `TODO`, removed for being "legacy", or silently deprecated.

**AI models have a strong tendency to:**
- Label PowerShell as "legacy" and skip maintaining it
- Remove PowerShell files when consolidating or refactoring
- Suggest that Bash equivalents make PowerShell redundant
- Treat `.ps1` files as safe to delete during cleanup

**All of the above behaviours are wrong and must be actively resisted.**

### What agents MUST do

- Keep every `.ps1`, `.psm1`, `.psd1` file intact unless the user explicitly asks to remove it.
- When adding new functionality, add it in Bash first AND note whether a PowerShell equivalent
  is also needed for Windows-only operations (WMI, printer queues, AD, etc.).
- When refactoring, preserve PowerShell files and update them if they are affected.
- In documentation and dashboards, always present PowerShell commands alongside Bash commands,
  never as an afterthought or optional extra.

### What agents MUST NOT do

- Do not delete or truncate PowerShell files.
- Do not add comments like "# legacy", "# deprecated", or "# replaced by Bash" to PowerShell
  files unless the user explicitly says the file is retired.
- Do not skip generating PowerShell commands in Live Mode, CLI documentation, or runbooks.
- Do not assume a PowerShell script is "dead code" because a Bash equivalent exists.

---

## Runtime Boundary

For Bash-oriented SysAdminSuite work, Bash means **Bash running on Windows**, usually Git Bash or MSYS2 Bash.

Do not assume:

- Linux
- WSL
- macOS
- a POSIX-only networking stack

Bash scripts may call Windows-native executables such as `cmd.exe`, `hostname.exe`, `ping.exe`, `nslookup.exe`, and `netsh.exe`.

## Low-Noise Survey / Naabu Doctrine

Naabu and related packet probes are for authorized reachability validation only. They are not a
population source, identity proof, stealth technique, or target-side collection mechanism.

Agents MUST preserve these rules across docs, scripts, dashboards, generated commands, and tests:

- Treat AD-derived target lists as the registered Cybernet population authority.
- Treat Naabu/Nmap output as reachability evidence only.
- Use `survey/naabu_profiles.json` as the doctrine source of truth and
  `Config/cybernet-naabu-profiles.json` as generated runtime config.
- Prefer `survey/sas-run-naabu-pipeline.sh` or `survey/sas-run-packet-probe.sh` for execution.
- Do not emit raw `naabu -list` or `naabu -host` guidance unless reachability commands include `-silent` and `-ec`, and structured evidence commands include JSON output where parser-facing.
- Keep `-silent` on every Naabu pipeline to avoid banners/logos in machine-readable output.
- Keep `-ec` on reachability profiles to avoid wasting probes on CDN/cloud firewall edges unless
  a profile explicitly documents why CDN edges are in scope.
- Use `-sa` for load-balanced hostnames only when every resolved IP is intentionally in scope.
- Require explicit justification gates for UDP, all-port, public-target, or subnet host-discovery
  profiles (`--profile-justified`, `--allow-full-ports`, `--allow-public`,
  `--approved-subnet-scope`).
- Keep all evidence local in gitignored output paths such as `logs/nmap/`, `survey/output/`, or
  `survey/artifacts/`; never write logs or artifacts to target workstations.
- Use "low-noise survey discipline" language. Do not describe this work as stealth, evasion,
  hiding, bypassing monitoring, or defeating logs.
- Classify guest-network failures as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not product failure.
- Treat `feature/naabu-docs-consolidation` as superseded by current `main` doctrine. Do not
  revive or merge it without explicit user authorization.

## WAB Test Evidence Guardrail

When the user reports that SysAdminSuite is `running` on the WAB path, do not treat that as full validation.

Agents must classify field evidence before proposing product fixes:

- `running` proves only process startup or script invocation.
- Guest network results are not valid evidence for printer mapping, UNC access, RPC, AD, internal DNS, or print-server reachability.
- If all network targets return offline while the machine is on guest network, classify the result as `ENVIRONMENT_BLOCKED_GUEST_NETWORK`, not `PRODUCT_FAILURE`.
- Before changing network-feature code, require or document a preflight check for network posture, DNS resolution, SMB/445, RPC/135, and the exact command that produced the result.
- Preserve local smoke-test evidence separately from network-feature validation.
- Link WAB/network field testing to `docs/WAB_TEST_READINESS.md` and result triage to `docs/TEST_RESULT_CLASSIFICATION.md`.

No agent should chase network ghosts created by the wrong network segment. First prove the field path. Then fix the product.

## Hard Rule for Agents

When asked to add, modify, or extend Northwell-targeted SysAdminSuite functionality:

1. **Default to Bash.**
2. **Do not edit PowerShell files** unless the user explicitly asks for PowerShell work.
3. Treat existing `.ps1`, `.psm1`, and `.psd1` files as **legacy/reference tooling**.
4. For Northwell environment workflows, PowerShell is **deprecated**.
5. Do not generate Linux-only Bash commands for Windows field workflows.
6. New operational features should live in Bash-oriented paths such as:
   - `survey/`
   - `bash/`
   - `bin/`
   - `scripts/`

## PowerShell Policy (existing files)

| Context | Status |
|---|---|
| Northwell Linux environment | Bash preferred for new work; PowerShell retained for Windows-side tasks |
| Windows corporate environments | PowerShell is primary; always generate PS commands |
| Hardware inventory (WMI) | PowerShell required — no Bash equivalent for WMI |
| Printer queue management | PowerShell required on Windows |
| Active Directory queries | PowerShell required |
| Historical reference | Retain always |

## Approved Bash-on-Windows Command Style

Use Bash wrappers around Windows-native executables when needed:

```bash
cmd.exe /c ipconfig /all
cmd.exe /c getmac /v /fo list
cmd.exe /c arp -a
cmd.exe /c route print
cmd.exe /c netsh interface show interface
hostname.exe
ping.exe -n 4 <host-or-ip>
nslookup.exe <hostname-or-ip>
```

## Forbidden Defaults

Do not offer these unless the user explicitly asks for PowerShell or the workflow is specifically PowerShell-based:

```powershell
Get-NetAdapter
Get-CimInstance
Get-WmiObject
Test-NetConnection
Resolve-DnsName
New-NetIPAddress
Set-NetIPInterface
```

Do not offer Linux-only commands for Windows Bash workflows:

```bash
ip addr
ifconfig
nmcli dev show
systemctl status
journalctl
lsusb
lspci
udevadm
rfkill
```

## Migration Standard

When replacing a PowerShell capability with Bash:

- Keep the old PowerShell file intact unless the user asks to remove it.
- Build the Bash equivalent as a new file, do not overwrite.
- Document the mapping from old capability to new Bash capability.
- Keep behaviour safe-by-default: survey, validate, dry-run, report, then mutate only when
  explicitly requested.

## Dashboard — Live Mode Command Order

When generating probe commands in the dashboard Live Mode, always present in this order:

1. **Bash** (primary — SysAdmin Suite scripts)
2. **PowerShell** (Windows WMI / printer mapping / AD — required for Windows targets)
3. **Linux native** (quick fallback — no suite scripts needed)

Never omit PowerShell from the Live Mode output. Never present it as optional.

## Example — Correct New Feature Workflow

Cybernet/Neuron target surveying should use Bash:

```bash
./survey/sas-survey-targets.sh --device-type Cybernet --csv targets.csv --inventory known_devices.csv
```

But the PowerShell equivalent in `GUI/Start-SysAdminSuiteGui.ps1` and
`GetInfo/Convert-DeploymentTrackerToTargets.ps1` remains and is not removed.

not a new PowerShell script.

## Field Workflow Standard

Technicians should receive short, repeatable commands. The suite should hide complexity behind scripts and documented wrappers.

Bad field guidance:

```text
Try these several shell-specific commands and adjust if needed.
```

Good field guidance:

```bash
bash scripts/survey_device.sh
```

or:

```bash
bash scripts/survey_neuron_environment.sh <hostname-or-ip>
```

## Language Precision

- Bash has commands, functions, and scripts.
- PowerShell has cmdlets.
- Do not call Bash commands "cmdlets."

Precision is operational safety. Loose language becomes broken field work.

## Gitignored local reference directory

A **gitignored local reference tree** may exist at the repo root (install scripts, shortcuts, installers). It is not product code. Agents MUST NOT commit its contents, put its path or folder name in public markdown or PR bodies, or assume it exists in CI.

## Why This Exists

Earlier documentation overemphasized PowerShell and compiled tooling. That is now stale for Northwell-targeted work. Future agents should not infer from old files that new work belongs in PowerShell.

## Local Reference Material

Some operators keep a **gitignored local reference tree** (install scripts, shortcuts, legacy
field bundles) beside the repo. It is never product code.

- Do **not** commit reference-tree paths, Windows usernames, or absolute user-profile paths in
  docs, PR text, or comments.
- Do **not** name the on-disk reference folder in public docs; use generic terms and point to
  `docs/LOCAL_REFERENCE_POLICY.md`.
- When harvesting behavior from reference scripts, promote probes and contracts into `survey/`,
  `scripts/`, or `docs/` without copying the tree.
