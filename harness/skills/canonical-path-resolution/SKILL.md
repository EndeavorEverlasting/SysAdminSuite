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

The current working directory is candidate evidence only. A fresh PowerShell session may start in the user profile, System32, a terminal default directory, another repository, or a non-filesystem provider such as `HKLM:` or `Cert:`. Do **not** start location discovery with `git rev-parse --show-toplevel`; that command requires the shell to already be inside a Git worktree and therefore cannot own repository location. A non-filesystem provider location is valid execution context but is never normalized into a filesystem candidate path.

A handoff/NEXT COMMAND for a workstation default-branch checkout may depend only on artifacts already contained in refreshed remote default. If a resolver, validator, or helper exists only in an unmerged PR, integrate it first or use provider-side proof; do not tell the operator to expect that artifact locally.

Resolve the Windows Desktop Known Folder first and compose `Desktop\Dev\SysAdminSuite`. Before executing any script from that directory, use non-executing Git identity checks to prove the directory is the SysAdminSuite checkout, its origin is one of the exact supported GitHub URL forms, and Git can actually read the checkout. Missing, conflicting, or Git-I/O-unhealthy canonical state never authorizes cloning SysAdminSuite into another convenient directory.

Use one complete paste block. The outer scriptblock is mandatory: native-command failures do not honor `$ErrorActionPreference` by themselves, so every native call is checked and a failure terminates the single pasted unit before later commands can run.

```powershell
& {
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

    & git -C $repo status --porcelain=v1 --untracked-files=no --ignore-submodules=dirty *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "PRESERVE: canonical path exists but Git I/O is unhealthy at $repo. Do not fetch, reset, clean, create worktrees, or overwrite it until unique work is inventoried and the storage state is repaired."
    }

    Set-Location -LiteralPath $repo
    Write-Host "CANONICAL + PROVED: $repo"
}
```

After the resolver is integrated into refreshed default branch, the same atomic block may additionally verify that `scripts/Resolve-SasCanonicalDevelopmentPath.ps1` is tracked and unmodified, then invoke it with `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ... -RequireCheckout`. Never make an unmerged helper a prerequisite for a default-branch workstation command.

Only after checkout identity **and Git I/O health** are proved may the continuation use `git fetch`, inspect status/log, reconcile the canonical checkout, or create an isolated worktree beneath the registered worktree root.

## Execution context and production/use safety

Before a path-sensitive command, record the actual terminal host, shell/interpreter process, PowerShell edition/version, current provider/location, OS/runtime boundary, and execution target. A terminal application is not the shell, and a Windows process is not proof that the operator-to-target relation is `LOCAL`. Native indicators may prove CI, PowerShell remoting, or SSH; an authorized invocation may explicitly scope the execution target. Otherwise record the target as `UNKNOWN` and do not guess a target-specific mutation command.

The production/use path is a **consumer path**, not a convenient second checkout. Resolve `PROD_USE_STATE` independently as `ACTIVE`, `QUIESCED`, `OFFLINE`, `UNKNOWN`, or `NOT_APPLICABLE`. `UNKNOWN` is not idle. An existing production directory without bounded consumer/quiescence evidence remains `UNKNOWN`, and ad-hoc pull/reset/rebuild/copy/edit/regeneration there is blocked.

For `windows-admin-box`, the registry owns these roles:

- development: OS-resolved Desktop Known Folder -> `Dev\SysAdminSuite`;
- worktrees: `%LOCALAPPDATA%\SysAdminSuite\worktrees`;
- updater sync clone: `%LOCALAPPDATA%\SysAdminSuite\sync-cache`;
- updater field-ready worktrees: `%LOCALAPPDATA%\SysAdminSuite\field-ready` and `field-ready-*`;
- production/use: `C:\SASAL`;
- production entrypoint: `C:\SASAL\Bootstrap-SysAdminSuiteAutoLogon.cmd`;
- production update authority: `scripts/Refresh-SasOperatorCommand.ps1` through its tracked refresh/bootstrap boundary.

The updater-owned sync-cache and field-ready copies are bounded implementation locations, not alternate canonical development checkouts. Inventory and preserve them; do not promote them to development authority or clean them merely because a different path is canonical.

If development and production resolve to the same physical path, every development write is production-impacting. `ACTIVE` or `UNKNOWN` blocks mutation until the tracked contract proves quiescence/in-place safety. If either path is a junction, symlink, mount, or other unresolved reparse point, record `UNKNOWN_REPARSE_POINT_RELATION` and block mutation until physical relation is proved; lexical path inequality is not enough. When paths are proved separate, normal edits/builds/tests stay in canonical development or an approved worktree, then cross the registered updater/promotion boundary; never copy a partial tree into production.

Classify bounded observed locations as `CLONE`, `WORKTREE`, `INSTALL`, `MIRROR`, `CACHE`, `OUTPUT`, `BACKUP`, or `UNKNOWN`. Inventory before cleanup. Nothing becomes disposable merely because it is noncanonical; preserve dirty, unpushed, unique, separately owned, or not-yet-inspected state.

## Procedure

1. Read `harness/api/canonical-path-registry.json`.
2. Record execution context before path-sensitive mutation. A Windows process alone leaves execution target `UNKNOWN`; use native remote/CI evidence or an explicit authorized target scope before target-sensitive mutation.
3. Treat a non-filesystem PowerShell provider location as execution context only; do not force it through filesystem normalization.
4. Resolve all four profile parameters and record their sources before choosing a machine-role profile.
5. Resolve one compatible machine-role profile; do not choose a directory from model preference.
6. Compose the canonical development checkout from `{desktop_dev_root}\SysAdminSuite` for the Windows profiles instead of assuming `%USERPROFILE%\Desktop\Dev`.
7. Before any checkout-owned executable is trusted, prove the composed directory with non-executing Git top-level and exact-origin checks, then require `git status --porcelain=v1 --untracked-files=no --ignore-submodules=dirty` to return zero. A path is not canonical-proved merely because `rev-parse` and `config` work.
8. Treat `ROOT_UNAVAILABLE` and `MULTIPLE_ROOTS` as conflicting OneDrive profile evidence; do not continue to canonical checkout proof until reconciled.
9. If Git read/index/file access fails, classify the checkout `CONFLICT_GIT_IO_UNHEALTHY`, preserve it, and stop before fetch/reset/clean/worktree creation.
10. Use `scripts/Resolve-SasCanonicalDevelopmentPath.ps1` only after that artifact is present on the refreshed default branch or from another already-trusted source; current directory never overrides the tracked rule.
11. Classify the candidate and bounded known copies as CLONE/WORKTREE/INSTALL/MIRROR/CACHE/OUTPUT/BACKUP/UNKNOWN, including refresh-owned `sync-cache` and `field-ready*`; no cleanup is authorized by path identity alone.
12. Resolve `PROD_USE_STATE` and physical path relation before any production-path write. ACTIVE/UNKNOWN blocks ad-hoc mutation; unresolved reparse semantics block any mutation that assumes path separation.
13. Keep these proofs separate: remote default contains SHA; canonical development checkout current; production/use path current; real operator entrypoint observes current.
14. For remote freshness, delegate to `harness/workflows/repository-freshness-before-launch.yaml`.
15. Preserve dirty or unique work. Use a Git worktree under the registered temporary root for parallel writers instead of making another mutable clone.
16. For an installed/field runtime, require its owning updater/seal/manifest proof. A GitHub merge or fresh clone is insufficient.
17. For operator execution, delegate to `harness/workflows/operator-execution-route.yaml` and require the registered entrypoint to observe the intended runtime.
18. Report the first unproven state and its owning continuation; do not claim workstation deployment from repository evidence.

## PowerShell operator-block integrity

When an operator command contains control flow or more than one native command whose later execution depends on earlier success, emit **one outer scriptblock** and check `$LASTEXITCODE` after each material native command. `$ErrorActionPreference = 'Stop'` does not convert native nonzero exit codes into terminating PowerShell errors.

Forbidden recurrence pattern:

```text
command 1 fails -> prompt returns -> already-pasted command 2 still runs -> later state is misclassified
```

Also forbidden: a NEXT COMMAND that requires a helper that exists only on an unmerged feature branch while the operator is on the default branch.

## Expected outputs

- execution-context receipt: terminal host, shell/interpreter, PowerShell edition/version, current provider/location, runtime boundary, execution target, and target evidence source;
- selected machine-role profile;
- resolved `os`, `user`, `onedrive_enabled`, and `desktop_dev_root` with source provenance;
- canonical development checkout and worktree root;
- candidate role plus CLONE/WORKTREE/INSTALL/MIRROR/CACHE/OUTPUT/BACKUP/UNKNOWN class;
- bounded known-location inventory including updater-owned sync-cache/field-ready copies and `cleanup_authorized=false`;
- Git I/O health disposition;
- production/use path, `PROD_USE_STATE`, physical path relation/evidence, and mutation guard;
- registered production update authority/boundary when applicable;
- real operator entrypoint authority;
- all four proof-state dispositions;
- one exact continuation when a state remains unproven.

## Proof ceiling

This skill proves execution-context evidence, user-profile/path authority, bounded copy classification, Git checkout usability, conservative production-use state, and routing only. It does not prove production quiescence, mutate a product target, or prove deployment/runtime success.
