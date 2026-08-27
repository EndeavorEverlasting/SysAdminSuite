# Canonical Path Resolution Skill

## Trigger

Load this skill when a task needs to locate SysAdminSuite, create or select a worktree, update a checkout, resolve an installed/served/field runtime, choose a real operator entrypoint, or diagnose a command that is present remotely but missing at the path being used.

## Required inputs

Every user profile resolves four independent parameters: `os`, `user`, `onedrive_enabled`, and `desktop_dev_root`.

- `os`: explicit override or observed local operating system;
- `user`: explicit override or current local account identity;
- `onedrive_enabled`: explicit override or observed OneDrive-root environment state;
- `desktop_dev_root`: explicit override or the OS-resolved Desktop known-folder plus `Dev`;
- requested operation;
- machine/profile role when known;
- candidate repository/runtime path when supplied;
- current Git identity and status when repository currentness matters;
- intended commit when pinned evidence exists.

The OneDrive toggle never chooses the Desktop path. A user can have OneDrive enabled without Desktop redirection, or have a redirected Desktop whose exact location must come from the OS/explicit `desktop_dev_root`. The canonical checkout is composed from `desktop_dev_root`, not inferred from the toggle. `ROOT_UNAVAILABLE` or `MULTIPLE_ROOTS` is conflicting profile evidence and must not be promoted to canonical checkout proof.

## From-anywhere Windows bootstrap

The current working directory is candidate evidence only. A fresh PowerShell session may start in the user profile, System32, a terminal default directory, or another repository. Do **not** start location discovery with `git rev-parse --show-toplevel`; that command requires the shell to already be inside a Git worktree and therefore cannot own repository location.

Resolve the Windows Desktop Known Folder first and compose `Desktop\Dev\SysAdminSuite`. Before executing any script from that directory, use non-executing Git identity checks to prove the directory is the SysAdminSuite checkout, its origin is one of the exact supported GitHub URL forms, and the resolver itself has no working-tree or staged modification relative to the current checkout. Only then execute the tracked resolver. Missing or conflicting canonical state never authorizes cloning SysAdminSuite into another convenient directory.

Use one complete paste block:

```powershell
$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
if ([string]::IsNullOrWhiteSpace($desktop)) {
    throw 'Desktop Known Folder unresolved; canonical SysAdminSuite development path is UNKNOWN.'
}
$repo = [IO.Path]::GetFullPath((Join-Path (Join-Path $desktop 'Dev') 'SysAdminSuite'))
if (-not (Test-Path -LiteralPath $repo -PathType Container)) {
    throw "MISSING canonical SysAdminSuite checkout: $repo. Do not create a fallback clone elsewhere."
}
$top = (& git -C $repo rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$top) -or -not ([IO.Path]::GetFullPath(([string]$top).Trim())).Equals($repo, [StringComparison]::OrdinalIgnoreCase)) {
    throw "CONFLICT: canonical-looking path is not the SysAdminSuite Git top-level: $repo"
}
$origin = ([string](& git -C $repo config --get remote.origin.url 2>$null)).Trim().TrimEnd('/')
if ($LASTEXITCODE -ne 0) { throw "CONFLICT: unable to resolve origin for $repo" }
$allowedOrigins = @(
    'https://github.com/EndeavorEverlasting/SysAdminSuite',
    'https://github.com/EndeavorEverlasting/SysAdminSuite.git',
    'git@github.com:EndeavorEverlasting/SysAdminSuite',
    'git@github.com:EndeavorEverlasting/SysAdminSuite.git',
    'ssh://git@github.com/EndeavorEverlasting/SysAdminSuite',
    'ssh://git@github.com/EndeavorEverlasting/SysAdminSuite.git'
)
if ($allowedOrigins -notcontains $origin) {
    throw "CONFLICT: canonical-looking path has the wrong repository origin: $origin"
}
$resolverRel = 'scripts/Resolve-SasCanonicalDevelopmentPath.ps1'
& git -C $repo ls-files --error-unmatch -- $resolverRel *> $null
if ($LASTEXITCODE -ne 0) { throw "CONFLICT: canonical resolver is not tracked at $resolverRel" }
& git -C $repo diff --quiet -- $resolverRel
if ($LASTEXITCODE -ne 0) { throw "PRESERVE: canonical resolver has working-tree changes; do not execute or overwrite it." }
& git -C $repo diff --cached --quiet -- $resolverRel
if ($LASTEXITCODE -ne 0) { throw "PRESERVE: canonical resolver has staged changes; do not execute or overwrite it." }
Set-Location -LiteralPath $repo
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\Resolve-SasCanonicalDevelopmentPath.ps1 -RequireCheckout
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

`powershell.exe` is deliberately used for the child resolver because every supported Windows PowerShell 5.1 host has it and the resolver declares `#Requires -Version 5.1`. PowerShell 7 callers remain supported because they can launch the inbox Windows PowerShell child for this read-only preflight.

Only after that proof may the continuation use `git fetch`, inspect status, reconcile the canonical checkout, or create an isolated worktree beneath the registered worktree root.

## Procedure

1. Read `harness/api/canonical-path-registry.json`.
2. Resolve all four profile parameters and record their sources before choosing a machine-role profile.
3. Resolve one compatible machine-role profile; do not choose a directory from model preference.
4. Compose the canonical development checkout from `{desktop_dev_root}\SysAdminSuite` for the Windows profiles instead of assuming `%USERPROFILE%\Desktop\Dev`.
5. On Windows, before executing the checkout-owned resolver, prove the composed directory with non-executing Git top-level, exact origin, tracked-file, and resolver-diff checks; then use `scripts/Resolve-SasCanonicalDevelopmentPath.ps1` for the full receipt. Current directory never overrides the tracked rule.
6. Treat `ROOT_UNAVAILABLE` and `MULTIPLE_ROOTS` as conflicting OneDrive profile evidence; do not continue to canonical checkout proof until reconciled.
7. Classify the candidate as canonical development, production/use, isolated worktree, ephemeral acquisition, or unknown.
8. Keep these proofs separate: remote default contains SHA; canonical development checkout current; production/use path current; real operator entrypoint observes current.
9. For remote freshness, delegate to `harness/workflows/repository-freshness-before-launch.yaml`.
10. Preserve dirty or unique work. Use a Git worktree under the registered temporary root for parallel writers instead of making another mutable clone.
11. For an installed/field runtime, require its owning updater/seal/manifest proof. A GitHub merge or fresh clone is insufficient.
12. For operator execution, delegate to `harness/workflows/operator-execution-route.yaml` and require the registered entrypoint to observe the intended runtime.
13. Report the first unproven state and its owning continuation; do not claim workstation deployment from repository evidence.

## PowerShell operator-block integrity

When an operator command needs `if`/`else`, loops, `try`/`catch`, or another multi-line control-flow construct, emit the **entire construct in one copy/paste block**. PowerShell requires `else` to remain part of the same parsed `if` statement.

Correct:

```powershell
if ($ready) {
    Write-Host 'READY'
} else {
    Write-Host 'NOT READY'
}
```

Forbidden handoff pattern:

```text
first paste:  if (...) { ... }
second paste: else { ... }
```

The second submission attempts to invoke a command named `else`.

## Expected outputs

- selected machine-role profile;
- resolved `os`, `user`, `onedrive_enabled`, and `desktop_dev_root` with source provenance;
- path classification;
- canonical development checkout composed from the resolved Desktop Dev root;
- production/use path or not-applicable reason;
- temporary worktree root;
- real operator entrypoint authority;
- all four proof-state dispositions;
- one exact continuation when a state remains unproven.

## Proof ceiling

This skill proves user-profile/path authority and routing only. It does not mutate a product target or prove deployment/runtime success.
