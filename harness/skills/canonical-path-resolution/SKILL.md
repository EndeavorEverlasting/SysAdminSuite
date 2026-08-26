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

The OneDrive toggle never chooses the Desktop path. A user can have OneDrive enabled without Desktop redirection, or have a redirected Desktop whose exact location must come from the OS/explicit `desktop_dev_root`. The canonical checkout is composed from `desktop_dev_root`, not inferred from the toggle.

## Procedure

1. Read `harness/api/canonical-path-registry.json`.
2. Resolve all four profile parameters and record their sources before choosing a machine-role profile.
3. Resolve one compatible machine-role profile; do not choose a directory from model preference.
4. Compose the canonical development checkout from `{desktop_dev_root}\SysAdminSuite` for the Windows profiles instead of assuming `%USERPROFILE%\Desktop\Dev`.
5. Classify the candidate as canonical development, production/use, isolated worktree, ephemeral acquisition, or unknown.
6. Keep these proofs separate: remote default contains SHA; canonical development checkout current; production/use path current; real operator entrypoint observes current.
7. For remote freshness, delegate to `harness/workflows/repository-freshness-before-launch.yaml`.
8. Preserve dirty or unique work. Use a Git worktree under the registered temporary root for parallel writers instead of making another mutable clone.
9. For an installed/field runtime, require its owning updater/seal/manifest proof. A GitHub merge or fresh clone is insufficient.
10. For operator execution, delegate to `harness/workflows/operator-execution-route.yaml` and require the registered entrypoint to observe the intended runtime.
11. Report the first unproven state and its owning continuation; do not claim workstation deployment from repository evidence.

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
