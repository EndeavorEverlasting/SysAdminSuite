# Agent Instructions for SysAdminSuite

## Current Direction

SysAdminSuite is now a **Bash-first SysAdmin suite** for Northwell-targeted work.

The repository still contains PowerShell because those scripts work in other environments and remain useful as reference implementations. Do **not** remove them merely because they are PowerShell.

## Hard Rule for Agents

When asked to add, modify, or extend SysAdminSuite functionality:

1. **Default to Bash.**
2. **Do not edit PowerShell files** unless the user explicitly asks for PowerShell work.
3. Treat existing `.ps1`, `.psm1`, and `.psd1` files as **legacy/reference tooling**.
4. For Northwell environment workflows, PowerShell is **deprecated**.
5. New operational features should live in Bash-oriented paths such as:
   - `survey/`
   - `bash/`
   - `bin/`
   - `scripts/`
   - future Bash-specific modules

## PowerShell Status

PowerShell tooling in this repo is:

| Context | Status |
|---|---|
| Northwell environment | Deprecated. Do not extend unless explicitly requested. |
| Labs / unrestricted Windows environments | Acceptable. |
| Historical reference | Acceptable. |
| Migration source material | Acceptable. |

## Migration Standard

When replacing a PowerShell capability:

- Keep the old PowerShell file intact unless the user asks to remove it.
- Build the Bash equivalent as a new implementation.
- Document the mapping from old capability to new Bash capability.
- Keep behavior safe-by-default: survey, validate, dry-run, report, then mutate only when explicitly requested.

## Current Example

Cybernet and Neuron target surveying should use:

```bash
./survey/sas-survey-targets.sh --device-type Cybernet --csv targets.csv --inventory known_devices.csv
```

not a new PowerShell script.

## Why This Exists

Earlier documentation overemphasized PowerShell and compiled tooling. That is now stale for Northwell-targeted work. Future agents should not infer from old files that new work belongs in PowerShell.
