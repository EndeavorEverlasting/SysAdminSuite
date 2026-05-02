# PowerShell Legacy Policy

## Current Rule

PowerShell remains in SysAdminSuite because it works in some environments and contains useful operational knowledge.

For Northwell-targeted SysAdminSuite work, PowerShell is deprecated. New operational development should be Bash-first unless the user explicitly asks for PowerShell.

## Do Not Remove Existing PowerShell

Existing PowerShell files are not garbage. They are:

- working tools for permissive PowerShell environments
- reference implementations for Bash rewrites
- historical proof of capability
- test material for comparing future Bash behavior

Leave them alone unless asked to repair, port, archive, or delete them.

## Labeling Standard

When documenting PowerShell files, use language like:

> Acceptable in PowerShell-enabled environments. Deprecated for Northwell-targeted workflows. Prefer the Bash replacement for new development.

Avoid language that implies the PowerShell script is the preferred current path for Northwell.

## Agent Behavior

Agents should not:

- create new PowerShell scripts for Northwell workflows
- extend old PowerShell scripts without explicit instruction
- update GUI or Pester-first documentation as though PowerShell remains the main suite direction
- remove PowerShell scripts simply because they are deprecated in one environment

Agents should:

- build Bash replacements
- preserve old PowerShell tooling
- document migration mappings
- keep old examples clearly labeled as environment-specific legacy paths

## Migration Table

| Legacy PowerShell area | Bash migration posture |
|---|---|
| `GetInfo/*.ps1` hardware and device probes | Port behavior into Bash survey/probe modules |
| `Mapping/**/*.ps1` printer mapping | Preserve as legacy, migrate practical workflows into Bash/native tools |
| `QRTasks/*.ps1` QR task payloads | Preserve until Bash QR runners exist |
| `GUI/*.ps1` WinForms tooling | Legacy Windows control surface, not Northwell future direction |
| `Tests/Pester/*.ps1` | Legacy contract tests for PowerShell behavior only |

## Practical Standard

The Bash rewrite should keep the strongest behavior from the old tooling:

1. Safe default behavior.
2. Clear input contracts.
3. TXT, CSV, and JSON support where useful.
4. Dry-run before mutation.
5. Clean CSV/JSON outputs.
6. Human-readable reports.
7. No mystery state.

The bear may be old, but its claws are still sharp. Preserve the claws. Build the new animal in Bash.
