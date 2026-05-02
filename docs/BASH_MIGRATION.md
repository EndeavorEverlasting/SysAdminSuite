# Bash Migration Guidance

## Executive Rule

SysAdminSuite is being rewritten from PowerShell into Bash for Northwell-targeted use.

PowerShell is not being deleted. It is being preserved as working legacy tooling for environments where PowerShell is acceptable and as migration reference material.

## Environment Policy

| Environment | Preferred implementation | PowerShell status |
|---|---:|---|
| Northwell production / restricted endpoint workflows | Bash | Deprecated |
| General Windows labs | Bash or PowerShell | Acceptable |
| Offline development / reference work | Bash, PowerShell, C#, native as needed | Acceptable |
| Historical scripts already in repo | Preserve | Reference only unless requested |

## What Agents Should Do

When adding new functionality:

1. Start with Bash.
2. Put new operational scripts in Bash-oriented directories.
3. Leave old PowerShell scripts alone unless asked otherwise.
4. If a PowerShell script has useful behavior, port the behavior instead of editing the PowerShell file.
5. Document the replacement path.

## What Agents Should Not Do

- Do not create new `.ps1` files for Northwell-targeted workflows.
- Do not refactor existing PowerShell just because it appears outdated.
- Do not delete PowerShell scripts merely because they are deprecated for Northwell.
- Do not assume the root README's older PowerShell examples define the future architecture.

## Migration Pattern

For every migrated tool, use this pattern:

| Field | Meaning |
|---|---|
| Legacy capability | Existing PowerShell behavior being replaced |
| Bash replacement | New Bash script or module |
| Inputs | Typed args, TXT, CSV, JSON, environment variables |
| Outputs | CSV, JSON, logs, human-readable report |
| Safety posture | Dry-run, read-only, or mutating |
| Deployment posture | Northwell-safe or non-Northwell only |

## Current Migration Item: Cybernet / Neuron Survey Targets

Legacy idea:

- `GetInfo/Get-MachineInfo.ps1` probes host lists using PowerShell/WMI.

Bash replacement starting point:

- `survey/sas-survey-targets.sh`

Purpose:

- Accept hostnames, serials, and MAC addresses.
- Accept typed arguments, TXT, CSV, and JSON files.
- Normalize identifiers.
- Resolve serial/MAC-only targets through an optional inventory CSV.
- Output a clean survey manifest for Cybernet and Neuron work.

Example:

```bash
./survey/sas-survey-targets.sh \
  --device-type Neuron \
  --csv ./survey/input/neuron_targets.csv \
  --inventory ./survey/input/known_devices.csv \
  --output ./survey/output/neuron_survey_targets.csv
```

## Practical Northwell Rule

For Northwell work, Bash gets the first move. PowerShell sits on the bench unless specifically called in.
