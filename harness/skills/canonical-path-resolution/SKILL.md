# Canonical Path Resolution Skill

## Trigger

Load this skill when a task needs to locate SysAdminSuite, create or select a worktree, update a checkout, resolve an installed/served/field runtime, choose a real operator entrypoint, or diagnose a command that is present remotely but missing at the path being used.

## Required inputs

- requested operation;
- machine/profile when known;
- candidate repository/runtime path when supplied;
- current Git identity and status when repository currentness matters;
- intended commit when pinned evidence exists.

## Procedure

1. Read `harness/api/canonical-path-registry.json`.
2. Resolve one profile; do not choose a directory from model preference.
3. Classify the candidate as canonical development, production/use, isolated worktree, ephemeral acquisition, or unknown.
4. Keep these proofs separate: remote default contains SHA; canonical development checkout current; production/use path current; real operator entrypoint observes current.
5. For remote freshness, delegate to `harness/workflows/repository-freshness-before-launch.yaml`.
6. Preserve dirty or unique work. Use a Git worktree under the registered temporary root for parallel writers instead of making another mutable clone.
7. For an installed/field runtime, require its owning updater/seal/manifest proof. A GitHub merge or fresh clone is insufficient.
8. For operator execution, delegate to `harness/workflows/operator-execution-route.yaml` and require the registered entrypoint to observe the intended runtime.
9. Report the first unproven state and its owning continuation; do not claim workstation deployment from repository evidence.

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

- selected profile;
- path classification;
- canonical development checkout;
- production/use path or not-applicable reason;
- temporary worktree root;
- real operator entrypoint authority;
- all four proof-state dispositions;
- one exact continuation when a state remains unproven.

## Proof ceiling

This skill proves path authority and routing only. It does not mutate a product target or prove deployment/runtime success.
