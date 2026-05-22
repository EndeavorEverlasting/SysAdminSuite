# SysAdminSuite Convergence Compatibility Contract

## Purpose

This document defines how divergent SysAdminSuite branches must be converged without losing working functionality.

The repo now has multiple valid runtime lanes and several historical branches with useful payloads. The goal is not to crown one branch and burn the village. The goal is to preserve working tools, separate runtime lanes cleanly, and merge only current, reviewable work into `main`.

## Core Rule

Compatibility means no runtime lane may erase another runtime lane.

SysAdminSuite currently has three legitimate lanes:

| Lane | Role | Merge posture |
|---|---|---|
| C# / .NET / native | Long-term compiled tooling direction for restricted endpoints and GUI-grade productization | Preferred for durable product work |
| PowerShell | Maintained optional tooling for labs, build hosts, legacy workflows, parity checks, and Windows admin environments that allow scripts | Preserve and test, do not delete blindly |
| Bash-on-Windows | Field-survey and read-only probe lane using Git Bash or MSYS2 with Windows-native executables | Preserve for fast field use and restricted scripting scenarios |

No PR should replace one lane with another unless it includes a parity plan and explicit migration evidence.

## Non-Negotiables

- Do not merge stale branches directly into `main`.
- Do not use stale branches as new base branches.
- Do not delete PowerShell files to make Bash or compiled tooling look cleaner.
- Do not delete Bash-on-Windows field tools because the README says compiled tooling is preferred.
- Do not commit generated CSV, HTML, tracker exports, real hostnames, MACs, serials, rooms, users, or live site data.
- Do not let direct-main patches remain undocumented.
- Do not treat Replit/Linux test failure as product failure when the intended runtime is Bash-on-Windows.
- Do not replace a dispatcher file wholesale when only one task registration should be harvested.

## Merge Strategy

All convergence work should follow this sequence:

1. Start from current `main`.
2. Compare the candidate branch against current `main`.
3. Classify every changed file as one of:
   - already absorbed
   - safe additive file
   - needs manual merge
   - obsolete or superseded
   - reject with reason
4. Harvest useful files into a fresh branch from current `main`.
5. Keep wrappers and adapters additive wherever possible.
6. Run the relevant tests.
7. Open a clean PR with a compatibility checklist.
8. Close or supersede stale PRs only after the clean replacement path exists.

## Conflict Resolution Priorities

When two branches conflict, use this order:

1. Preserve data safety and read-only behavior.
2. Preserve field usability for technicians.
3. Preserve existing PowerShell functionality unless there is a tested replacement.
4. Preserve Bash-on-Windows behavior where field docs require it.
5. Preserve compiled/native direction for long-term productization.
6. Prefer small adapters over rewrites.
7. Prefer explicit deprecation notes over silent deletion.

## Required Compatibility Matrix

Every convergence PR must state which lanes it affects.

| Check | Required when |
|---|---|
| `dotnet test SysAdminSuite.sln -c Release` | Any C#/.NET/native contract or solution impact |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Pester5Suite.ps1` | Any PowerShell, QRTasks, GetInfo, Mapping, ActiveDirectory, GUI script impact |
| `bash tests/bash/smoke-bash-windows-runtime.sh` | Any Bash-on-Windows survey or transport impact |
| Offline fixture run for live serial probe | Any live serial probe or dashboard impact |
| Manual dispatcher review | Any change to `QRTasks/Invoke-TechTask.ps1` or similar registry/dispatcher files |

If a test cannot be run in Replit because the runtime is wrong, mark it as `not runnable in Replit runtime`, not as failed product functionality.

## PR Compatibility Checklist

Every convergence PR should include this checklist:

- [ ] Branch starts from current `main`.
- [ ] Stale branch was compared, not merged blindly.
- [ ] Added files are additive or explicitly justified.
- [ ] Modified dispatcher/registry files were manually merged, not overwritten.
- [ ] PowerShell functionality preserved unless replacement is proven.
- [ ] Bash-on-Windows behavior preserved where applicable.
- [ ] Compiled/native direction not contradicted.
- [ ] Generated outputs and real device/site data excluded.
- [ ] Relevant test lane identified.
- [ ] Any tests not run include the reason.

## Comment Template For Stale PRs

Use this when marking an old PR as superseded:

```md
Convergence decision:

This PR should not be merged directly into `main` because the branch is stale or divergent.

Useful payload will be harvested into a fresh branch from current `main` using the compatibility contract:

- `docs/CONVERGENCE_COMPATIBILITY_CONTRACT.md`
- `docs/BRANCH_CONVERGENCE_2026-05-22.md`

Rules:

- preserve runtime lanes
- harvest additive files
- manually merge dispatcher changes
- run relevant tests
- close this PR only after replacement path exists
```

## Functional Loss Watchlist

Watch these areas during convergence:

| Area | Risk | Required posture |
|---|---|---|
| QRTasks dispatcher | Whole-file overwrite can drop current task registrations | Manual merge only |
| Bash survey scripts | Linux defaults can break Git Bash/MSYS2 field use | Bash-on-Windows contract controls |
| PowerShell GetInfo scripts | Compiled tooling direction can tempt deletion | Preserve until replacement has parity |
| Live serial probe | Runtime mismatch can be misdiagnosed in Replit | Validate with offline fixtures and Bash-on-Windows |
| Neuron maintenance tooling | PR #6 contains unmerged useful payload | Harvest into fresh branch, do not merge stale branch |
| Generated dashboards/CSVs | Public repo data leakage | Keep ignored and uncommitted |

## Throttle Rule

For Cybernet and Neuron ascertainment, throttle means maximum concurrent target probes.

Timeout controls how long one target gets before the probe gives up.
Throttle controls how many targets are being probed at once.

Recommended defaults:

| Context | Throttle |
|---|---:|
| Smoke test | 2 |
| Conservative field batch | 8 |
| Larger LAN batch | 12 |
| Aggressive run requiring explicit approval | 15 |

The Bash live serial lane should eventually expose `--throttle`. Until then, do not imply it has concurrency protection where it does not.

## Final Principle

Harvest what lives. Preserve every runtime lane. Delete nothing useful without proof.

No branch soup. No theatrical rewrites. No functionality left bleeding in the snow.
