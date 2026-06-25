# Northwell Registry-First Software Verification Doctrine

## Purpose

This doctrine defines a Northwell-compatible software installation verification lane for SysAdminSuite.

The lane augments existing working legacy tooling. It does not replace the existing PowerShell registry install-diff pipeline, Cybernet survey workflow, auto-logon assessment, or dashboard launcher.

## Core Principle

Software installation verification should prefer registry evidence first.

Installer exit code is execution evidence. It is not proof that software is installed.

A workstation is considered verified only when post-install evidence confirms the installed state.

## Northwell Runtime Pivot

For this lane, the primary runtime is:

1. `cmd.exe` and `reg.exe` for registry reads
2. Bash for repo-style orchestration
3. Python for parsing and normalization

PowerShell remains available in existing legacy/advanced lanes, but this lane does not add new PowerShell-first functionality.

## Evidence Hierarchy

| Priority | Evidence source | Authority |
|---:|---|---|
| 1 | Registry uninstall keys under `HKLM` 64-bit and WOW6432Node views | Primary install proof |
| 2 | Product-specific registry keys from the software evidence catalog | Strong product-specific proof |
| 3 | File path and version checks | Fallback proof |
| 4 | Service existence/status checks | Fallback proof |
| 5 | Installer exit code | Execution result only |
| 6 | Operator note or dashboard note | Human context only |

Fallback evidence is allowed, but it must be labeled as fallback.

## OS and Security Logging Posture

Registry queries, file checks, service checks, command execution, and process creation can naturally produce operating-system, endpoint-protection, and security telemetry.

SysAdminSuite must not attempt to suppress, clear, bypass, hide, or evade that logging.

Mitigation means limiting unnecessary activity and making the operator intent clear:

- Use approved target manifests only.
- Query only the keys and fallback paths needed for the selected software ID.
- Prefer local or small approved batches before broader use.
- Do not run live checks from CI.
- Do not use credentials in this lane.
- Do not mutate target workstations.
- Do not write registry values.
- Do not run installers from this verification lane.
- Keep raw live evidence under gitignored output paths.
- Label environment blocks honestly instead of calling them product failures.

This lane is designed for transparent, low-noise verification discipline. It is not a log-suppression or evasion mechanism.

## Status Values

| Status | Meaning |
|---|---|
| `installed_registry_confirmed` | Registry evidence confirms the software is installed. |
| `installed_registry_partial` | Some registry evidence exists, but it is incomplete or ambiguous. |
| `installed_fallback_confirmed` | Registry proof is missing, but fallback file/service evidence indicates installation. |
| `not_installed` | No registry or fallback evidence confirms installation. |
| `ambiguous` | Conflicting or duplicate evidence requires review. |
| `verification_failed` | The verification logic failed for a tool/runtime reason. |
| `environment_blocked` | The environment blocked evidence collection, such as network, permission, policy, or remote registry access. |

## Evidence Strength Values

| Evidence strength | Meaning |
|---|---|
| `registry_uninstall_key` | Match from Windows uninstall registry view. |
| `registry_custom_key` | Match from product-specific registry key. |
| `fallback_file` | Match from configured file path or version. |
| `fallback_service` | Match from configured service query. |
| `none` | No confirming evidence found. |

## Live Evidence Policy

Do not commit live outputs.

The following are local/gitignored evidence only:

- raw `reg.exe` output
- normalized CSV/JSON summaries from live machines
- target manifests containing real hostnames
- generated dashboards
- workstation names, IPs, MACs, serials, AD exports, or location-specific artifacts

Recommended live output roots:

- `survey/output/`
- `logs/registry/`
- `logs/targets/`

## Relationship to Existing Registry Install Diff

The existing registry install-diff pipeline remains useful for before/after snapshots and deeper localhost analysis.

This Northwell lane is different:

- It is CMD/reg.exe-first.
- It is verification-focused, not install-diff-focused.
- It does not execute installers.
- It does not require PowerShell.
- It labels fallback evidence clearly.

Both lanes can coexist.

## Safe Operating Rule

Use the least necessary check to answer the install-state question.

When the environment blocks evidence collection, report `environment_blocked` and stop. Do not broaden the check or reframe the result as a software failure.
