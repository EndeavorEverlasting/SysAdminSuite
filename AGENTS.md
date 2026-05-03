# Agent Instructions for SysAdminSuite

## Language Hierarchy

SysAdminSuite targets both Northwell-specific Linux environments and general Windows corporate
environments. The tooling hierarchy is:

1. **Bash** — primary for new operational work (survey, audit, transport, preflight)
2. **PowerShell** — active Windows tooling; used in real corporate deployments daily
3. **Linux native** (dig, ping, nc, arp, etc.) — quick checks without suite scripts
4. **C** — planned for performance-critical probe components
5. **Rust** — planned for systems-level tooling
6. **Lua** — planned for lightweight scripting and configuration

This hierarchy exists now and will grow. Agents MUST NOT rearrange or collapse it.

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

## Bash Policy (new features)

When asked to add or extend SysAdminSuite functionality:

1. Default to Bash.
2. Do not edit PowerShell files unless the user explicitly asks for PowerShell work.
3. New operational features live in Bash-oriented paths:
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
